defmodule Aeutil.Mixfile do
  use Mix.Project

  def project do
    [
      app: :aeutil,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
