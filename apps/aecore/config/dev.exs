use Mix.Config

config :aecore, :persistence, write_options: [sync: true, disable_wal: false]

config :aecore, :pow, params: {"./lean16", "-t 5", 16}

config :aecore, :peers, ranch_acceptors: 10

config :aecore, :miner, resumed_by_default: false

config :aecore, :pow_module, Aecore.Pow.Cuckoo
