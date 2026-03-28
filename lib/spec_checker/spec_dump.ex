defmodule SpecChecker.SpecDump do
  @moduledoc """
  Extracts @spec annotations from compiled BEAM files.
  Reads specs directly from beam binaries without loading modules into the VM.
  Can also resolve behaviour callback specs for @impl functions.
  """

  @type spec_entry :: %{
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          signature: String.t(),
          source: :module | :behaviour,
          behaviour: String.t() | nil
        }

  @spec extract_from_beam(String.t(), keyword()) :: {:ok, [spec_entry()]} | {:error, String.t()}
  def extract_from_beam(beam_path, opts \\ []) do
    deps_dir = Keyword.get(opts, :deps_dir)

    with {:ok, binary} <- read_beam(beam_path) do
      module_name = beam_path_to_module(beam_path)
      own_specs = extract_own_specs(module_name, binary)
      callback_specs = extract_callback_specs(module_name, binary, deps_dir)

      # Deduplicate: if a function has both an own @spec and a callback spec, prefer the own
      own_keys = MapSet.new(own_specs, fn s -> {s.name, s.arity} end)

      filtered_callbacks =
        Enum.reject(callback_specs, fn s -> MapSet.member?(own_keys, {s.name, s.arity}) end)

      {:ok, own_specs ++ filtered_callbacks}
    end
  end

  @spec extract_from_dir(String.t(), keyword()) :: {:ok, [spec_entry()]} | {:error, String.t()}
  def extract_from_dir(dir, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)
    deps_dir = Keyword.get(opts, :deps_dir, infer_deps_dir(dir))

    case File.ls(dir) do
      {:ok, files} ->
        entries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".beam"))
          |> Enum.sort()
          |> Enum.flat_map(fn file ->
            path = Path.join(dir, file)

            case extract_from_beam(path, deps_dir: deps_dir) do
              {:ok, specs} -> specs
              {:error, _} -> []
            end
          end)
          |> maybe_filter_prefix(prefix)

        {:ok, entries}

      {:error, reason} ->
        {:error, "could not read directory #{dir}: #{inspect(reason)}"}
    end
  end

  @spec format_line(spec_entry()) :: String.t()
  def format_line(%{
        module: mod,
        name: name,
        arity: arity,
        signature: sig,
        source: source,
        behaviour: behaviour
      }) do
    suffix =
      case {source, behaviour} do
        {:behaviour, b} when is_binary(b) -> " [callback: #{b}]"
        {:behaviour, _} -> " [callback]"
        _ -> ""
      end

    "#{mod}.#{name}/#{arity} :: #{sig}#{suffix}"
  end

  def format_line(%{module: mod, name: name, arity: arity, signature: sig}) do
    "#{mod}.#{name}/#{arity} :: #{sig}"
  end

  # --- Private: own specs ---

  defp extract_own_specs(module_name, binary) do
    case Code.Typespec.fetch_specs(binary) do
      {:ok, specs} -> format_specs(module_name, specs, :module, nil)
      :error -> []
    end
  end

  # --- Private: callback spec resolution ---

  defp extract_callback_specs(_module_name, _binary, nil), do: []

  defp extract_callback_specs(module_name, binary, deps_dir) do
    behaviours = get_behaviours(binary)

    Enum.flat_map(behaviours, fn behaviour_mod ->
      behaviour_name =
        behaviour_mod |> to_string() |> String.replace_leading("Elixir.", "")

      case find_behaviour_beam(behaviour_mod, deps_dir) do
        {:ok, behaviour_binary} ->
          case Code.Typespec.fetch_callbacks(behaviour_binary) do
            {:ok, callbacks} -> format_specs(module_name, callbacks, :behaviour, behaviour_name)
            :error -> []
          end

        :error ->
          []
      end
    end)
  end

  defp get_behaviours(binary) do
    case :beam_lib.chunks(binary, [:attributes]) do
      {:ok, {_mod, [attributes: attrs]}} ->
        Keyword.get_values(attrs, :behaviour) |> List.flatten()

      _ ->
        []
    end
  end

  defp find_behaviour_beam(behaviour_mod, deps_dir) do
    beam_filename = "#{behaviour_mod}.beam"

    case File.ls(deps_dir) do
      {:ok, lib_dirs} ->
        Enum.find_value(lib_dirs, :error, fn lib ->
          path = Path.join([deps_dir, lib, "ebin", beam_filename])

          case File.read(path) do
            {:ok, binary} -> {:ok, binary}
            {:error, _} -> nil
          end
        end)

      {:error, _} ->
        :error
    end
  end

  # --- Private: shared helpers ---

  defp read_beam(path) do
    case File.read(path) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, "could not read #{path}: #{inspect(reason)}"}
    end
  end

  defp beam_path_to_module(path) do
    path
    |> Path.basename(".beam")
    |> String.replace_leading("Elixir.", "")
  end

  defp format_specs(module_name, specs, source, behaviour) do
    Enum.flat_map(specs, fn {{name, arity}, spec_forms} ->
      Enum.map(spec_forms, fn spec ->
        quoted = Code.Typespec.spec_to_quoted(name, spec)
        signature = Macro.to_string(quoted)

        %{
          module: module_name,
          name: to_string(name),
          arity: arity,
          signature: signature,
          source: source,
          behaviour: behaviour
        }
      end)
    end)
  end

  defp maybe_filter_prefix(entries, nil), do: entries

  defp maybe_filter_prefix(entries, prefix) do
    Enum.filter(entries, &String.starts_with?(&1.module, prefix))
  end

  defp infer_deps_dir(ebin_dir) do
    parent = Path.dirname(ebin_dir)
    grandparent = Path.dirname(parent)

    if Path.basename(ebin_dir) == "ebin" and File.dir?(grandparent) do
      grandparent
    else
      nil
    end
  end
end
