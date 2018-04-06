defmodule Aehttpclient.Mixfile do
  use Mix.Project

  def project do
    [
      app: :aehttpclient,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.0.0"},
      {:aeutil, in_umbrella: true},
      {:aehttpserver, in_umbrella: true}
    ]
  end
end
