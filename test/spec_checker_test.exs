defmodule SpecChecker.FunctionSpecsTest do
  use ExUnit.Case, async: true

  alias SpecChecker.FunctionSpecs

  @tmp_dir System.tmp_dir!()

  defp write_tmp_file(name, content) do
    path = Path.join(@tmp_dir, "sc_#{name}.ex")
    File.write!(path, content)
    path
  end

  describe "check_file/1" do
    test "passes when all functions have specs" do
      path =
        write_tmp_file("all_specs", """
        defmodule Foo do
          @spec bar(integer()) :: :ok
          def bar(x), do: :ok

          @spec baz() :: String.t()
          def baz, do: "hello"
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "reports missing specs for public functions" do
      path =
        write_tmp_file("missing_pub", """
        defmodule Foo do
          def bar(x), do: :ok
        end
        """)

      assert {:ok, [%{name: :bar, arity: 1, kind: :def, line: 2}]} =
               FunctionSpecs.check_file(path)
    end

    test "reports missing specs for private functions" do
      path =
        write_tmp_file("missing_priv", """
        defmodule Foo do
          @spec bar() :: :ok
          def bar, do: do_bar()

          defp do_bar, do: :ok
        end
        """)

      assert {:ok, [%{name: :do_bar, arity: 0, kind: :defp, line: 5}]} =
               FunctionSpecs.check_file(path)
    end

    test "handles multi-clause functions" do
      path =
        write_tmp_file("multi_clause", """
        defmodule Foo do
          @spec process(atom()) :: :ok | :error
          def process(:ok), do: :ok
          def process(:error), do: :error
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "reports once for multi-clause without spec" do
      path =
        write_tmp_file("multi_no_spec", """
        defmodule Foo do
          def process(:ok), do: :ok
          def process(:error), do: :error
        end
        """)

      assert {:ok, [%{name: :process, arity: 1, line: 2}]} = FunctionSpecs.check_file(path)
    end

    test "ignores macros" do
      path =
        write_tmp_file("macros", """
        defmodule Foo do
          defmacro my_macro(x), do: x
          defmacrop my_private_macro(x), do: x
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "handles @impl true" do
      path =
        write_tmp_file("impl_true", """
        defmodule MyServer do
          use GenServer

          @impl true
          def init(state), do: {:ok, state}
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "handles @impl ModuleName" do
      path =
        write_tmp_file("impl_module", """
        defmodule MyWorker do
          @impl Oban.Worker
          def perform(job), do: :ok

          @impl GenServer
          def init(state), do: {:ok, state}
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "handles guards" do
      path =
        write_tmp_file("guards", """
        defmodule Foo do
          @spec bar(integer()) :: :ok
          def bar(x) when is_integer(x), do: :ok
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "handles nested modules" do
      path =
        write_tmp_file("nested", """
        defmodule Outer do
          @spec outer_fn() :: :ok
          def outer_fn, do: :ok

          defmodule Inner do
            def inner_fn, do: :ok
          end
        end
        """)

      assert {:ok, [%{name: :inner_fn, arity: 0, line: 6}]} = FunctionSpecs.check_file(path)
    end

    test "handles default arguments" do
      path =
        write_tmp_file("defaults", """
        defmodule Foo do
          @spec greet(String.t(), String.t()) :: String.t()
          def greet(name, greeting \\\\ "Hello"), do: "\#{greeting}, \#{name}"
        end
        """)

      assert {:ok, []} = FunctionSpecs.check_file(path)
    end

    test "returns error for unparseable file" do
      path = write_tmp_file("bad", "defmodule Foo do def bar(")
      assert {:error, _} = FunctionSpecs.check_file(path)
    end

    test "returns error for nonexistent file" do
      assert {:error, _} = FunctionSpecs.check_file("/nonexistent/path.ex")
    end

    test "empty module returns empty list" do
      path = write_tmp_file("empty", "defmodule Empty do\nend")
      assert {:ok, []} = FunctionSpecs.check_file(path)
    end
  end

  describe "check_files/1" do
    test "aggregates results from multiple files" do
      path1 = write_tmp_file("m1", "defmodule A do\n  def a_fn, do: :ok\nend")

      path2 =
        write_tmp_file("m2", "defmodule B do\n  @spec b_fn() :: :ok\n  def b_fn, do: :ok\nend")

      assert {:ok, results} = FunctionSpecs.check_files([path1, path2])
      assert [%{name: :a_fn}] = Map.get(results, path1)
      assert [] = Map.get(results, path2)
    end
  end
end
