defmodule Aecore.Chain.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Chain.Header
  alias Aeutil.Bits
  alias Aecore.Keys

  @type t :: %Header{
          height: non_neg_integer(),
          prev_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          target: non_neg_integer(),
          nonce: non_neg_integer(),
          time: non_neg_integer(),
          miner: Keys.pubkey(),
          version: non_neg_integer()
        }

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :root_hash,
    :target,
    :nonce,
    :time,
    :miner,
    :version,
    :pow_evidence
  ]

  use ExConstructor

  @spec create(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.pubkey(),
          non_neg_integer()
        ) :: Header.t()

  def create(height, prev_hash, txs_hash, root_hash, target, nonce, time, miner, version) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      target: target,
      nonce: nonce,
      time: time,
      miner: miner,
      version: version
    }
  end

  def base58c_encode(bin) do
    Bits.encode58c("bh", bin)
  end

  def base58c_decode(<<"bh$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end
end
