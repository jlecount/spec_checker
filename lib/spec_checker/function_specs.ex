defmodule SpecChecker.FunctionSpecs do
  @moduledoc """
  AST-based checker that identifies Elixir functions missing @spec annotations.
  Parses source files and walks the AST to find def/defp without a preceding @spec.
  """

  @type missing_spec :: %{
          name: atom(),
          arity: non_neg_integer(),
          kind: :def | :defp,
          line: pos_integer()
        }

  @spec check_file(String.t()) :: {:ok, [missing_spec()]} | {:error, String.t()}
  def check_file(path) do
    case File.read(path) do
      {:ok, source} -> check_source(source)
      {:error, reason} -> {:error, "could not read #{path}: #{inspect(reason)}"}
    end
  end

  @spec check_source(String.t()) :: {:ok, [missing_spec()]} | {:error, String.t()}
  def check_source(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        {:ok, find_missing_specs(ast)}

      {:error, {location, message, token}} ->
        line = if is_list(location), do: Keyword.get(location, :line, "?"), else: location
        {:error, "parse error at line #{line}: #{message}#{token}"}
    end
  end

  @spec check_files([String.t()]) ::
          {:ok, %{String.t() => [missing_spec()] | {:error, String.t()}}}
  def check_files(paths) do
    results =
      Map.new(paths, fn path ->
        case check_file(path) do
          {:ok, missing} -> {path, missing}
          {:error, reason} -> {path, {:error, reason}}
        end
      end)

    {:ok, results}
  end

  @typep walker_state :: %{specs: MapSet.t(), impl: boolean(), results: [missing_spec()]}

  # --- AST Walking ---

  @spec find_missing_specs(Macro.t()) :: [missing_spec()]
  defp find_missing_specs(ast) do
    {_ast, state} = walk(ast, %{specs: MapSet.new(), impl: false, results: []})

    state.results
    |> Enum.reverse()
    |> deduplicate()
  end

  @spec walk(Macro.t(), walker_state()) :: {nil, walker_state()}
  defp walk({:defmodule, _meta, [_alias, [do: body]]}, state) do
    {_body, inner_state} = walk(body, %{state | specs: MapSet.new(), impl: false})
    {nil, %{state | results: inner_state.results}}
  end

  defp walk({:__block__, _meta, exprs}, state) do
    state = walk_sequential(exprs, state)
    {nil, state}
  end

  defp walk({:@, _meta, [{:spec, _spec_meta, [{:"::", _, [{name, _, args} | _]} | _]}]}, state) do
    arity = spec_arity(args)
    {nil, %{state | specs: MapSet.put(state.specs, {name, arity}), impl: false}}
  end

  defp walk({:@, _meta, [{:impl, _impl_meta, [value]}]}, state) do
    {nil, %{state | impl: value != false}}
  end

  defp walk({kind, meta, [head | _rest]}, state) when kind in [:def, :defp] do
    {name, arity} = extract_function_head(head)
    line = Keyword.get(meta, :line, 0)

    has_spec? = MapSet.member?(state.specs, {name, arity})
    is_impl? = state.impl

    state = %{state | impl: false}

    if has_spec? or is_impl? do
      {nil, state}
    else
      {nil,
       %{state | results: [%{name: name, arity: arity, kind: kind, line: line} | state.results]}}
    end
  end

  # Catch-all for other AST nodes
  defp walk({_form, _meta, children}, state) when is_list(children) do
    state = Enum.reduce(children, state, fn child, acc -> elem(walk(child, acc), 1) end)
    {nil, state}
  end

  defp walk(_other, state), do: {nil, state}

  @spec walk_sequential([Macro.t()], walker_state()) :: walker_state()
  defp walk_sequential(exprs, state) do
    Enum.reduce(exprs, state, fn expr, acc ->
      elem(walk(expr, acc), 1)
    end)
  end

  # --- Function head extraction ---

  @spec extract_function_head(Macro.t()) :: {atom(), non_neg_integer()} | {atom(), String.t()}
  defp extract_function_head({:when, _meta, [head | _guards]}), do: extract_function_head(head)
  defp extract_function_head({name, _meta, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp extract_function_head({name, _meta, nil}) when is_atom(name), do: {name, 0}
  defp extract_function_head(other), do: {:unknown, inspect(other)}

  # --- Spec arity extraction ---

  @spec spec_arity(nil | [Macro.t()] | Macro.t()) :: non_neg_integer()
  defp spec_arity(nil), do: 0
  defp spec_arity(args) when is_list(args), do: length(args)
  defp spec_arity(_), do: 0

  # --- Deduplication for multi-clause functions ---

  @spec deduplicate([missing_spec()]) :: [missing_spec()]
  defp deduplicate(results) do
    Enum.uniq_by(results, fn %{name: name, arity: arity} -> {name, arity} end)
  end
end
