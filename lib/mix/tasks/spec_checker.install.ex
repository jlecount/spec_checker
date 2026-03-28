defmodule Mix.Tasks.SpecChecker.Install do
  @moduledoc """
  Builds the check_specs escript and copies it to a directory on your PATH.

      mix spec_checker.install --dir ~/.local/bin

  If --dir is not provided, prints the built escript path and exits.
  """

  use Mix.Task

  @shortdoc "Build and install the check_specs escript"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])

    Mix.Task.run("escript.build")

    escript_path = Path.join(File.cwd!(), "check_specs")

    case Keyword.get(opts, :dir) do
      nil ->
        Mix.shell().info("Escript built at: #{escript_path}")
        Mix.shell().info("To install, run: mix spec_checker.install --dir <path>")

      dir ->
        dir = Path.expand(dir)

        unless File.dir?(dir) do
          Mix.raise("Directory does not exist: #{dir}")
        end

        dest = Path.join(dir, "check_specs")
        File.cp!(escript_path, dest)
        File.chmod!(dest, 0o755)
        Mix.shell().info("Installed check_specs to #{dest}")
    end
  end
end
