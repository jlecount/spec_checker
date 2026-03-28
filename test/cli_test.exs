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
