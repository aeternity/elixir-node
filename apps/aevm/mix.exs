defmodule Aevm.MixProject do
  use Mix.Project

  def project do
    [
      app: :aevm,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
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
