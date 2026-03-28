defmodule SpecChecker.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias SpecChecker.CLI

  @tmp_dir System.tmp_dir!()

  defp write_tmp_file(name, content) do
    path = Path.join(@tmp_dir, "sc_cli_#{name}.ex")
    File.write!(path, content)
    path
  end

  defp decode_json(output), do: Jason.decode!(output)

  describe "check mode (JSON default)" do
    test "exits 0 when all functions have specs" do
      path =
        write_tmp_file("good", """
        defmodule Good do
          @spec ok() :: :ok
          def ok, do: :ok
        end
        """)

      output = capture_io(fn -> assert CLI.run([path]) == 0 end)
      result = decode_json(output)
      assert result["status"] == "pass"
      assert result["total_missing"] == 0
    end

    test "exits 1 when functions missing specs" do
      path =
        write_tmp_file("bad", """
        defmodule Bad do
          def no_spec, do: :oops
        end
        """)

      output = capture_io(fn -> assert CLI.run([path]) == 1 end)
      result = decode_json(output)
      assert result["status"] == "fail"
      assert result["total_missing"] == 1
      [entry] = result["missing"]
      assert entry["name"] == "no_spec"
    end
  end

  describe "check mode (text)" do
    test "exits 0 with success message" do
      path =
        write_tmp_file("text_good", """
        defmodule Good do
          @spec ok() :: :ok
          def ok, do: :ok
        end
        """)

      output = capture_io(fn -> assert CLI.run(["--format", "text", path]) == 0 end)
      assert output =~ "All functions have @spec"
    end
  end

  describe "dump mode" do
    test "exits 2 for nonexistent directory" do
      output = capture_io(fn -> assert CLI.run(["--dump", "/nonexistent/ebin"]) == 2 end)
      result = decode_json(output)
      assert result["status"] == "error"
    end
  end

  describe "--output flag" do
    @ebin_dir "_build/dev/lib/spec_checker/ebin"

    test "writes dump to file" do
      output_path = Path.join(@tmp_dir, "sc_output_test_#{System.unique_integer([:positive])}.txt")

      capture_io(fn ->
        assert CLI.run(["--dump", "--format", "text", "--output", output_path, @ebin_dir]) == 0
      end)

      assert File.exists?(output_path)
      contents = File.read!(output_path)
      assert contents =~ "SpecChecker"
    end

    test "does not write file when --require-clean fails" do
      output_path = Path.join(@tmp_dir, "sc_clean_fail_#{System.unique_integer([:positive])}.txt")

      project_dir = Path.join(@tmp_dir, "sc_project_#{System.unique_integer([:positive])}")
      lib_dir = Path.join(project_dir, "lib")
      ebin_dir = Path.join([project_dir, "_build", "dev", "lib", "my_app", "ebin"])
      File.mkdir_p!(lib_dir)
      File.mkdir_p!(ebin_dir)
      File.write!(Path.join(project_dir, "mix.exs"), "")

      File.write!(Path.join(lib_dir, "bad.ex"), """
      defmodule Bad do
        def no_spec, do: :oops
      end
      """)

      capture_io(fn ->
        assert CLI.run([
                 "--dump",
                 "--require-clean",
                 "--project-root",
                 project_dir,
                 "--output",
                 output_path,
                 ebin_dir
               ]) == 1
      end)

      refute File.exists?(output_path)
    end

    test "writes file when --require-clean passes" do
      output_path = Path.join(@tmp_dir, "sc_clean_pass_#{System.unique_integer([:positive])}.txt")

      project_dir = Path.join(@tmp_dir, "sc_project_clean_#{System.unique_integer([:positive])}")
      lib_dir = Path.join(project_dir, "lib")
      ebin_dir = Path.join([project_dir, "_build", "dev", "lib", "my_app", "ebin"])
      File.mkdir_p!(lib_dir)
      File.mkdir_p!(ebin_dir)

      File.write!(Path.join(lib_dir, "good.ex"), """
      defmodule Good do
        @spec ok() :: :ok
        def ok, do: :ok
      end
      """)

      capture_io(fn ->
        assert CLI.run([
                 "--dump",
                 "--require-clean",
                 "--project-root",
                 project_dir,
                 "--output",
                 output_path,
                 ebin_dir
               ]) == 0
      end)

      assert File.exists?(output_path)
    end
  end

  describe "flags" do
    test "no args shows usage" do
      output = capture_io(:stderr, fn -> assert CLI.run([]) == 1 end)
      assert output =~ "Usage"
    end

    test "--help exits 0" do
      output = capture_io(fn -> assert CLI.run(["--help"]) == 0 end)
      assert output =~ "Usage"
      assert output =~ "--format"
    end
  end
end
