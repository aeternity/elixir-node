defmodule Aecore.Chain.MicroHeader do
  @moduledoc """
  Module defining the MicroHeader structure
  """
  alias Aecore.Chain.MicroHeader

  @type t :: %MicroHeader{
          height: non_neg_integer(),
          pof_hash: binary(),
          prev_hash: binary(),
          prev_key_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          time: non_neg_integer(),
          version: non_neg_integer(),
          signature: binary()
        }

  defstruct [
    :height,
    :pof_hash,
    :prev_hash,
    :prev_key_hash,
    :txs_hash,
    :root_hash,
    :time,
    :version,
    :signature
  ]
end
