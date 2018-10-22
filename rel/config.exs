Path.join(["rel", "plugins", "*.exs"])
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
    default_release: :default,
    default_environment: Mix.env()

environment :dev_build do
  set dev_mode: true
  set include_erts: true
  set cookie: :"secret_dev_build"
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :"%h?QkPuoHK;RFk4r4&z.GF%Mye*c|:e?o!;zcW>Efj6`,c^T5kgr5>GxEr3rv.uF"
end

release :elixir_node do
  set version: System.get_env("VERSION")
  set applications: [
        :aecore,
        :aehttpclient,
        :aehttpserver,
        :aeutil,
        :aevm
      ]
end
