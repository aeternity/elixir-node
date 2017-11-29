use Mix.Config

config :aecore, :persistence,
  path: Path.absname("./priv_dev2/rox_db")

config :aecore, :pow,
  nif_path: Path.absname("apps/aecore/priv/cuckoo/aec_pow_cuckoo20_nif"),
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 62,
    pow_evidence: [5_865, 33_461, 43_503, 72_290,
                   97_096, 102_579, 109_935, 110_807,
                   129_404, 135_480, 145_736, 174_409,
                   178_611, 180_359, 183_866, 197_227,
                   198_055, 206_373, 220_794, 221_908,
                   227_792, 240_266, 248_610, 311_225,
                   312_038, 315_739, 327_595, 334_270,
                   336_439, 345_186, 348_916, 357_090,
                   372_159, 444_132, 462_404, 464_127,
                   464_504, 495_627, 495_985, 497_109,
                   504_460, 510_965],
    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 3,
  peers_max_count: 4
