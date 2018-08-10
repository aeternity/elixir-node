use Mix.Config

import_config "dev.exs"

config :aecore, :pow, max_target_change: 0

config :aecore, :tx_data, minimum_fee: 1
