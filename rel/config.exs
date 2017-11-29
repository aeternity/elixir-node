Path.join(["rel", "plugins", "*.exs"])
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,

default_release: :default,
default_environment: Mix.env()


environment :dev do
  set dev_mode: true
  set include_erts: false
  set cookie: :"secret"
end

environment :dev1 do
  set dev_mode: true
  set include_erts: true
  set cookie: :"secret1"
end

environment :dev2 do
  set dev_mode: true
  set include_erts: false
  set cookie: :"secret2"
end

environment :dev3 do
  set dev_mode: true
  set include_erts: false
  set cookie: :"secret3"
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :"%h?QkPuoHK;RFk4r4&z.GF%Mye*c|:e?o!;zcW>Efj6`,c^T5kgr5>GxEr3rv.uF"
end

release :epoch_elixir do
  set version: "0.1.0"
  set applications: [
    :runtime_tools,
    aecore: :permanent,
    aehttpclient: :permanent,
    aehttpserver: :permanent
  ]
end
