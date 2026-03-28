defmodule SpecChecker.CLI do
  @moduledoc """
  CLI entry point for the standalone function specs checker and spec dumper.

  Two modes:
  - Check mode (default): verifies all functions have @spec annotations
  - Dump mode (--dump): extracts specs from compiled BEAM files

  Output format is JSON by default. Use --format text for human-readable output.

  Exit codes:
    0 — success (all specs present, or dump completed)
    1 — missing specs found (or no args)
    2 — errors encountered
  """

  alias SpecChecker.FunctionSpecs
  alias SpecChecker.SpecDump

  @typep format :: :json | :text
  @typep mode :: :check | :dump
  @typep missing_entry :: {String.t(), FunctionSpecs.missing_spec()}
  @typep error_entry :: %{file: String.t(), reason: String.t()}

  @spec main([String.t()]) :: no_return()
  def main(args) do
    args |> run() |> System.halt()
  end

  @spec run([String.t()]) :: 0 | 1 | 2
  def run([]),
    do:
      (
        IO.puts(:stderr, usage())
        1
      )

  def run(["--help"]),
    do:
      (
        IO.puts(usage())
        0
      )

  def run(args) do
    {mode, format, output, require_clean, project_root, rest} = parse_flags(args)

    case mode do
      :check -> check_files(rest, format)
      :dump -> dump_specs(rest, format, output, require_clean, project_root)
    end
  end

  # --- Flag parsing ---

  @spec parse_flags([String.t()]) :: {mode(), format(), String.t() | nil, boolean(), String.t() | nil, [String.t()]}
  defp parse_flags(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          dump: :boolean,
          format: :string,
          output: :string,
          require_clean: :boolean,
          project_root: :string
        ]
      )

    mode = if opts[:dump], do: :dump, else: :check
    format = if opts[:format] in ["json", "text"], do: String.to_atom(opts[:format]), else: :json
    output = opts[:output]
    require_clean = Keyword.get(opts, :require_clean, false)
    project_root = opts[:project_root]

    {mode, format, output, require_clean, project_root, rest}
  end

  # --- Check mode ---

  @spec check_files([String.t()], format()) :: 0 | 1 | 2
  defp check_files([], _format) do
    IO.puts(:stderr, usage())
    1
  end

  defp check_files(file_args, format) do
    {existing, missing} = Enum.split_with(file_args, &File.exists?/1)

    missing_file_errors =
      Enum.map(missing, fn path ->
        %{file: path, reason: "no such file"}
      end)

    {:ok, results} = FunctionSpecs.check_files(existing)

    {parse_errors, check_results} =
      Enum.split_with(results, fn {_path, result} -> match?({:error, _}, result) end)

    parse_error_entries =
      Enum.map(parse_errors, fn {path, {:error, reason}} ->
        %{file: path, reason: reason}
      end)

    all_errors = missing_file_errors ++ parse_error_entries

    missing_specs =
      Enum.flat_map(check_results, fn {path, specs} ->
        Enum.map(specs, &{path, &1})
      end)

    exit_code =
      cond do
        all_errors != [] -> 2
        missing_specs == [] -> 0
        true -> 1
      end

    output_check(format, exit_code, missing_specs, all_errors)
    exit_code
  end

  # --- Dump mode ---

  @spec dump_specs([String.t()], format(), String.t() | nil, boolean(), String.t() | nil) :: 0 | 1 | 2
  defp dump_specs([], _format, _output, _require_clean, _project_root) do
    IO.puts(:stderr, usage())
    1
  end

  defp dump_specs([dir | rest], format, output, require_clean, project_root) do
    if require_clean do
      root = project_root || infer_project_root(dir)

      case root do
        nil ->
          IO.puts(:stderr, "error: --require-clean needs --project-root or an ebin path under _build/")
          2

        root ->
          case run_clean_check(root, format) do
            :clean -> do_dump(dir, rest, format, output)
            {:dirty, exit_code} -> exit_code
          end
      end
    else
      do_dump(dir, rest, format, output)
    end
  end

  @spec infer_project_root(String.t()) :: String.t() | nil
  defp infer_project_root(ebin_dir) do
    ebin_dir
    |> Path.expand()
    |> do_infer_project_root()
  end

  @spec do_infer_project_root(String.t()) :: String.t() | nil
  defp do_infer_project_root("/"), do: nil

  defp do_infer_project_root(dir) do
    if File.exists?(Path.join(dir, "mix.exs")) do
      dir
    else
      do_infer_project_root(Path.dirname(dir))
    end
  end

  @spec do_dump(String.t(), [String.t()], format(), String.t() | nil) :: 0 | 2
  defp do_dump(dir, rest, format, output) do
    prefix = List.first(rest)
    opts = if prefix, do: [prefix: prefix], else: []

    case SpecDump.extract_from_dir(dir, opts) do
      {:ok, specs} ->
        write_or_print_dump(format, specs, output)
        0

      {:error, reason} ->
        output_dump_error(format, reason)
        2
    end
  end

  @spec write_or_print_dump(format(), [SpecDump.spec_entry()], String.t() | nil) :: :ok
  defp write_or_print_dump(format, specs, nil) do
    output_dump(format, specs)
  end

  defp write_or_print_dump(format, specs, path) do
    content =
      case format do
        :text ->
          Enum.map_join(specs, "\n", &SpecDump.format_line/1) <> "\n"

        :json ->
          build_dump_json(specs) |> Jason.encode!()
      end

    File.write!(path, content)
    IO.puts(:stderr, "Wrote #{length(specs)} specs to #{path}")
  end

  @spec run_clean_check(String.t(), format()) :: :clean | {:dirty, 1}
  defp run_clean_check(project_root, format) do
    root = Path.expand(project_root)
    lib_dir = Path.join(root, "lib")

    source_files =
      if File.dir?(lib_dir) do
        Path.wildcard(Path.join(lib_dir, "**/*.ex"))
      else
        []
      end

    if source_files == [] do
      :clean
    else
      {:ok, results} = FunctionSpecs.check_files(source_files)

      {_parse_errors, check_results} =
        Enum.split_with(results, fn {_path, result} -> match?({:error, _}, result) end)

      missing =
        Enum.flat_map(check_results, fn {path, specs} ->
          Enum.map(specs, &{path, &1})
        end)

      if missing == [] do
        :clean
      else
        output_check(format, 1, missing, [])
        {:dirty, 1}
      end
    end
  end

  # --- JSON output: check mode ---

  @spec output_check(format(), 0 | 1 | 2, [missing_entry()], [error_entry()]) :: :ok
  defp output_check(:json, exit_code, missing_specs, errors) do
    status = exit_code_to_status(exit_code)

    result = %{
      status: status,
      total_missing: length(missing_specs),
      missing:
        Enum.map(missing_specs, fn {path, spec} ->
          %{
            file: path,
            name: to_string(spec.name),
            arity: spec.arity,
            kind: to_string(spec.kind),
            line: spec.line
          }
        end),
      errors: errors
    }

    IO.puts(Jason.encode!(result))
  end

  # --- Text output: check mode ---

  defp output_check(:text, _exit_code, missing_specs, errors) do
    Enum.each(errors, fn err ->
      label = if err.reason == "no such file", do: "warning", else: "error"
      IO.puts(:stderr, "#{label}: #{err.file}: #{err.reason}")
    end)

    if missing_specs == [] do
      IO.puts("All functions have @spec annotations.")
    else
      report_missing_text(missing_specs)
    end
  end

  # --- JSON output: dump mode ---

  @spec output_dump(format(), [SpecDump.spec_entry()]) :: :ok
  defp output_dump(:json, specs) do
    IO.puts(Jason.encode!(build_dump_json(specs)))
  end

  @spec build_dump_json([SpecDump.spec_entry()]) :: map()
  defp build_dump_json(specs) do
    %{
      status: "pass",
      total_specs: length(specs),
      specs:
        Enum.map(specs, fn entry ->
          base = %{
            module: entry.module,
            name: entry.name,
            arity: entry.arity,
            signature: entry.signature,
            source: to_string(entry.source)
          }

          if entry.behaviour, do: Map.put(base, :behaviour, entry.behaviour), else: base
        end)
    }
  end

  # --- Text output: dump mode ---

  defp output_dump(:text, specs) do
    Enum.each(specs, fn entry ->
      IO.puts(SpecDump.format_line(entry))
    end)
  end

  # --- Error output: dump mode ---

  @spec output_dump_error(format(), String.t()) :: :ok
  defp output_dump_error(:json, reason) do
    IO.puts(Jason.encode!(%{status: "error", errors: [%{reason: reason}]}))
  end

  defp output_dump_error(:text, reason) do
    IO.puts(:stderr, "error: #{reason}")
  end

  # --- Helpers ---

  @spec exit_code_to_status(0 | 1 | 2) :: String.t()
  defp exit_code_to_status(0), do: "pass"
  defp exit_code_to_status(1), do: "fail"
  defp exit_code_to_status(2), do: "error"

  @spec report_missing_text([missing_entry()]) :: :ok
  defp report_missing_text(missing) do
    by_file = Enum.group_by(missing, &elem(&1, 0), &elem(&1, 1))

    IO.puts("Functions missing @spec annotations:\n")

    Enum.each(by_file, fn {file, specs} ->
      IO.puts("  #{file}")

      Enum.each(specs, fn spec ->
        IO.puts("    #{spec.kind} #{spec.name}/#{spec.arity} (line #{spec.line})")
      end)

      IO.puts("")
    end)

    count = length(missing)
    IO.puts("#{count} function#{if count == 1, do: "", else: "s"} missing @spec.")
  end

  @spec usage() :: String.t()
  defp usage do
    """
    Usage:
      check_specs [--format json|text] <file1.ex> [file2.ex ...]
      check_specs --dump [options] <ebin_dir> [ModulePrefix]

    Modes:
      (default)   Check that all functions in .ex files have @spec annotations.
                  Parses source via AST. Functions with @impl (any form) are exempt.
      --dump      Extract specs from compiled BEAM files in an ebin directory.
                  Reads bytecode directly — reflects what Dialyzer sees.

    Options:
      --format json          JSON output (default)
      --format text          Human-readable output
      --output <file>        Write dump output to file instead of stdout
      --require-clean        Only dump if all source files have specs (exit 1 otherwise)
      --project-root <dir>   Project root for --require-clean (inferred from ebin path if omitted)

    Exit codes:
      0  Success
      1  Missing specs found (check mode or --require-clean) or no args
      2  Errors encountered

    Examples:
      check_specs lib/**/*.ex
      check_specs --format text lib/my_app/server.ex
      check_specs --dump _build/dev/lib/my_app/ebin
      check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts
      check_specs --dump --require-clean --output specs.txt _build/dev/lib/my_app/ebin

    JSON output schema (check mode):
      {
        "status": "pass" | "fail" | "error",
        "total_missing": 0,
        "missing": [
          {"file": "lib/foo.ex", "name": "bar", "arity": 1, "kind": "def", "line": 12}
        ],
        "errors": [
          {"file": "lib/bad.ex", "reason": "parse error at line 3: ..."}
        ]
      }

    JSON output schema (dump mode):
      {
        "status": "pass" | "error",
        "total_specs": 5,
        "specs": [
          {"module": "MyApp.Foo", "name": "bar", "arity": 2,
           "signature": "bar(integer(), String.t()) :: :ok",
           "source": "module"},
          {"module": "MyApp.Worker", "name": "perform", "arity": 1,
           "signature": "perform(Oban.Job.t()) :: :ok",
           "source": "behaviour", "behaviour": "Oban.Worker"}
        ]
      }

    Dump mode automatically resolves callback specs from behaviour modules
    by searching sibling ebin directories under _build/dev/lib/.
    """
    |> String.trim()
  end
end
