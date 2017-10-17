defmodule Aecore.Structures.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Structures.Header

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :chain_state_hash,
    :difficulty_target,
    :nonce,
    :timestamp,
    :version
  ]

  use ExConstructor

  @type header() :: %Header{}

  @spec create(integer(), binary(), binary(), binary(), integer(), integer(), integer()) ::
          Header.header()
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
