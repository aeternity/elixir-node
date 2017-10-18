defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @type block :: %Block{}

  defstruct [:header, :txs]
  use ExConstructor

  def genesis_header() do
    %Header{
      height: 0,
      prev_hash: <<0::256>>,
      txs_hash: <<0::256>>,
      chain_state_hash: <<0 :: 256>>,
      timestamp: 1_507_275_094_308,
      nonce: 19,
      version: 1,
      difficulty_target: 1
    }
  end

  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: []}
  end
end
