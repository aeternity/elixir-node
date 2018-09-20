use Mix.Config

import_config "dev.exs"

config :logger, :console, level: :info

config :aecore, :pow_module, Aecore.Pow.Cuckoo
