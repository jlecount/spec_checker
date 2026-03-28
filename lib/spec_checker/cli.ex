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
    {mode, format, rest} = parse_flags(args)

    case mode do
      :check -> check_files(rest, format)
      :dump -> dump_specs(rest, format)
    end
  end

  # --- Flag parsing ---

  defp parse_flags(args) do
    {mode, args} = extract_mode(args)
    {format, args} = extract_format(args)
    {mode, format, args}
  end

  defp extract_mode(["--dump" | rest]), do: {:dump, rest}
  defp extract_mode(args), do: {:check, args}

  defp extract_format(["--format", fmt | rest]) when fmt in ["json", "text"] do
    {String.to_atom(fmt), rest}
  end

  defp extract_format(args), do: {:json, args}

  # --- Check mode ---

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

  defp dump_specs([], _format) do
    IO.puts(:stderr, usage())
    1
  end

  defp dump_specs([dir | rest], format) do
    prefix = List.first(rest)
    opts = if prefix, do: [prefix: prefix], else: []

    case SpecDump.extract_from_dir(dir, opts) do
      {:ok, specs} ->
        output_dump(format, specs)
        0

      {:error, reason} ->
        output_dump_error(format, reason)
        2
    end
  end

  # --- JSON output: check mode ---

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

  defp output_dump(:json, specs) do
    result = %{
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

    IO.puts(Jason.encode!(result))
  end

  # --- Text output: dump mode ---

  defp output_dump(:text, specs) do
    Enum.each(specs, fn entry ->
      IO.puts(SpecDump.format_line(entry))
    end)
  end

  # --- Error output: dump mode ---

  defp output_dump_error(:json, reason) do
    IO.puts(Jason.encode!(%{status: "error", errors: [%{reason: reason}]}))
  end

  defp output_dump_error(:text, reason) do
    IO.puts(:stderr, "error: #{reason}")
  end

  # --- Helpers ---

  defp exit_code_to_status(0), do: "pass"
  defp exit_code_to_status(1), do: "fail"
  defp exit_code_to_status(2), do: "error"

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

  defp usage do
    """
    Usage:
      check_specs [--format json|text] <file1.ex> [file2.ex ...]
      check_specs --dump [--format json|text] <ebin_dir> [ModulePrefix]

    Modes:
      (default)   Check that all functions in .ex files have @spec annotations.
                  Parses source via AST. Functions with @impl true are exempt.
      --dump      Extract specs from compiled BEAM files in an ebin directory.
                  Reads bytecode directly — reflects what Dialyzer sees.

    Options:
      --format json    JSON output (default)
      --format text    Human-readable output

    Exit codes:
      0  Success
      1  Missing specs found (check mode) or no args
      2  Errors encountered

    Examples:
      check_specs lib/**/*.ex
      check_specs --format text lib/my_app/server.ex
      check_specs --dump _build/dev/lib/my_app/ebin
      check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts

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
