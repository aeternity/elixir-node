use Mix.Config

import_config "dev.exs"

config :aecore, :pow,
  params: {"./mean28s-generic", "-t 5", 28},
  max_target_change: 1

config :aecore, :miner, resumed_by_default: true

config :aecore, :pow_module, Aecore.Pow.Cuckoo
