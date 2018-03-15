defmodule Aecore.Structures.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Structures.Header
  alias Aeutil.Bits

  @type t :: %Header{
    height: non_neg_integer(),
    prev_hash: binary(),
    txs_hash: binary(),
    root_hash: binary(),
    time: integer(),
    nonce: integer(),
    version: non_neg_integer(),
    target: integer()
  }

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :root_hash,
    :target,
    :nonce,
    :pow_evidence,
    :time,
    :version
  ]

  use ExConstructor

  @spec create(non_neg_integer(), binary(), binary(), binary(), integer(), non_neg_integer(), integer()) :: Header
  def create(height, prev_hash, txs_hash, root_hash, target, nonce, version) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      time: System.system_time(:milliseconds),
      nonce: nonce,
      version: version,
      target: target
    }
  end

  def bech32_encode(bin) do
    Bits.bech32_encode("bl", bin)
  end
end
