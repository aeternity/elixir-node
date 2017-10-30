defmodule Aecore.Mixfile do
  use Mix.Project

  def project do
    [app: :aecore,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.5",
     compilers: [:app, :make, :elixir],
     aliases: aliases(),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]

  end

  defp aliases do
    # Execute the usual mix clean and our Makefile clean task
    [clean: ["clean", "clean.make"]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :exconstructor], mod: {Aecore, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:my_app, in_umbrella: true}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:exconstructor, "~> 1.1"},
      {:gb_merkle_trees, git: "https://github.com/aeternity/gb_merkle_trees.git", ref: "4db7aad"}
    ]
  end
end

###################
# Make file Tasks #
###################

defmodule Mix.Tasks.Compile.Make do
  @moduledoc "Compiles helper in c_src"

  def run(_) do
    File.cd(Path.absname("apps/aecore/c_src"))
    {result, _error_code} = System.cmd("make", ['all'], stderr_to_stdout: true)
    Mix.shell.info result
    :ok
  end
end

defmodule Mix.Tasks.Clean.Make do
  def run(_) do
    ## Remove the compiled cpp files from `priv` dir
  end
end
