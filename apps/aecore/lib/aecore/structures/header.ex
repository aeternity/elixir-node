defmodule Aecore.Structures.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Structures.Header

  @type t :: %Header{
    height: non_neg_integer(),
    prev_hash: binary(),
    txs_hash: binary(),
    chain_state_hash: binary(),
    timestamp: integer(),
    nonce: integer(),
    version: non_neg_integer(),
    difficulty_target: integer()
  }

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :chain_state_hash,
    :difficulty_target,
    :nonce,
    :pow_evidence,
    :timestamp,
    :version
  ]

  use ExConstructor

  @spec create(non_neg_integer(), binary(), binary(), binary(), integer(), non_neg_integer(), integer()) :: Header.t()
  def create(height, prev_hash, txs_hash, chain_state_hash, difficulty, nonce, version) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      chain_state_hash: chain_state_hash,
      timestamp: System.system_time(:milliseconds),
      nonce: nonce,
      version: version,
      difficulty_target: difficulty
    }
  end
end
