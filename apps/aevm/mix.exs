defmodule Aevm.MixProject do
  use Mix.Project

  def project do
    [
      app: :aevm,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:sha3, [github: "szktty/erlang-sha3", ref: "dbdfd12", manager: :rebar]}
    ]
  end
end
