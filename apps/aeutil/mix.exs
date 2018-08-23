defmodule Aeutil.Mixfile do
  use Mix.Project

  def project do
    [
      app: :aeutil,
      version: "0.1.0",
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
    [{:sext, [github: "uwiger/sext", tag: "1.4.1", manager: :rebar, override: true]}]
  end
end
