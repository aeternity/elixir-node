defmodule Aehttpserver.Mixfile do
  use Mix.Project

  def project do
    [
      app: :aehttpserver,
      version: "0.0.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Aehttpserver, []},
      extra_applications: [:logger, :logger_file_backend, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:aeutil, in_umbrella: true},
      {:phoenix, "~> 1.3.0"},
      {:cowboy, "~> 1.0"},
      {:cors_plug, "~> 1.5.0"},
      {:erl_base58, "~> 0.0.1"},
      {:uuid, "~> 1.1.8"}
    ]
  end
end
