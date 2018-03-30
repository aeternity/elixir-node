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
          time: non_neg_integer(),
          nonce: non_neg_integer(),
          version: non_neg_integer(),
          target: non_neg_integer()
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

  @spec create(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: Header

  def create(height, prev_hash, txs_hash, root_hash, target, nonce, version, time) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      time: time,
      nonce: nonce,
      version: version,
      target: target
    }
  end

  def base58c_encode(bin) do
    Bits.encode58c("bh", bin)
  end

  def base58c_decode(<<"bh$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end
end
