defmodule Aecore.Block.Genesis do
  @moduledoc """
  Genesis Block
  """

  alias Aecore.Structures.Header
  alias Aecore.Structures.Block

  def genesis_header() do
    %Header{
      height: 0,
      prev_hash: <<0::size(256)>>,
      txs_hash: <<0::size(256)>>,
      difficulty_target: 1,
      nonce: 0,
      timestamp: System.system_time(:milliseconds),
      version: 1
    }
  end

  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: [] }
  end

end
