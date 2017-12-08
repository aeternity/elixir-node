use Mix.Config

config :aecore, :persistence,
  path: Path.absname("./priv_dev3/rox_db")

config :aecore, :peers,
  peers_target_count: 3,
  peers_max_count: 4
