defmodule EpochElixir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_node,
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.6.4",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        paths: [
          "_build/test/lib/aecore/ebin",
          "_build/test/lib/aehttpclient/ebin",
          "_build/test/lib/aehttpserver/ebin",
          "_build/test/lib/aeutil/ebin"
        ],
        ignore_warnings: "dialyzer.ignore-warnings"
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
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
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      {:credo, "~> 0.9.3", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.8.1", only: :test},
      {:idna,
       [
         git: "https://github.com/aeternity/erlang-idna",
         ref: "24bf647",
         manager: :rebar,
         override: true
       ]},
      {:ranch,
       git: "https://github.com/ninenines/ranch",
       ref: "55c2a9d623454f372a15e99721a37093d8773b48",
       override: true},
      {:edown, "~> 0.8", override: true}
    ]
  end
end
