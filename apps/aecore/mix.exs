defmodule Aecore.Mixfile do
  use Mix.Project

  def project do
    [
      app: :aecore,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      compilers: [:app, :make, :elixir],
      aliases: aliases(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
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
    [
      extra_applications: [:erlexec, :gproc, :logger, :rox, :exconstructor, :ranch, :jobs],
      mod: {Aecore, []}
    ]
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
      {:rox, "~> 2.2.1"},
      {:exconstructor, "~> 1.1"},
      {:logger_file_backend, "~> 0.0.10"},
      {:erl_base58, "~> 0.0.1"},
      {:exexec, "~> 0.1"},
      {:jobs, "~> 0.7.1"},
      {:ex_rlp, "~> 0.2.1"},
      {:gproc, "~> 0.6.1"},
      {:enoise, github: "aeternity/enoise", ref: "6d793b7"},
      {:merkle_patricia_tree, github: "aeternity/elixir-merkle-patricia-tree", ref: "0a763cc"}
    ]
  end
end

###################
# Make file Tasks #
###################

defmodule Mix.Tasks.Compile.Make do
  @moduledoc "Compiles helper in c_src"

  def run(_) do
    File.mkdir_p("apps/aecore/priv/cuckoo/bin")
    File.mkdir_p("apps/aecore/priv/cuckoo/lib")
    File.cd(Path.absname("apps/aecore/src/cuckoo/"))
    {result, _error_code} = System.cmd("make", ["all"], stderr_to_stdout: true)
    Mix.shell().info(result)
    :ok
  end
end

defmodule Mix.Tasks.Clean.Make do
  def run(_) do
    # Remove the compiled cpp files from `priv` dir
  end
end
