defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @type block :: %Block{}

  @current_block_version 1

  defstruct [:header, :txs]
  use ExConstructor

  def current_block_version do
    @current_block_version
  end

  def genesis_header() do
    %Header{
      height: 0,
      prev_hash: <<0::256>>,
      txs_hash: <<0::256>>,
      chain_state_hash: <<0 :: 256>>,
      timestamp: 1_507_275_094_308,
      nonce: 19,
      version: @current_block_version,
      difficulty_target: 1
    }
  end

  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: []}
  end
end
