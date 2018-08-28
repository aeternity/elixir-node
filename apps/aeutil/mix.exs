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
    [
      {:sext, [github: "uwiger/sext", tag: "1.4.1", manager: :rebar, override: true]},
      {:enacl, github: "aeternity/enacl", ref: "2f50ba6", override: true},
      {:gproc, "~> 0.6.1"},
      {:erl_base58, "~> 0.0.1"},
      {:merkle_patricia_tree,
       git: "https://github.com/aeternity/elixir-merkle-patricia-tree.git",
       ref: "595a436c554a4c2b7235f184fc9d2a910d333ca5",
       override: true},
      {:ex_rlp, "~> 0.2.1"}
    ]
  end
end
