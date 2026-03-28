defmodule SpecChecker do
  @moduledoc """
  Standalone Elixir typespec checker and BEAM spec extractor.

  Two modes:
  - Check: verify all functions in .ex files have @spec annotations (AST-based)
  - Dump: extract specs from compiled BEAM files, including behaviour callbacks
  """
end
