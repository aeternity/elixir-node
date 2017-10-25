defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @type block :: %Block{}

  @current_block_version 1
  @genesis_block_version @current_block_version

  defstruct [:header, :txs]
  use ExConstructor

  @spec current_block_version() :: integer()
  def current_block_version() do
    @current_block_version
  end

  @spec genesis_header() :: Header.header()
  def genesis_header() do
    %Header{
      height: 0,
      prev_hash: <<0::256>>,
      txs_hash: <<0::256>>,
      chain_state_hash: <<0 :: 256>>,
      timestamp: 1_507_275_094_308,
      nonce: 49,
      pow_evidence: [827073, 968001, 1367727, 2248958, 2496250, 3450285, 3762239,
                     4330454, 4753400, 6298861, 7633605, 8406300, 8427108, 8637289, 9074181,
                     11812624, 12065013, 12379945, 12636125, 13185509, 13304773, 16291222,
                     16913907, 17967337, 18585455, 19550321, 19557538, 21486461, 21542527,
                     22115004, 22608952, 22961192, 23009944, 24049559, 24093275, 24618494,
                     24790930, 24863623, 25203962, 26777546, 27127749, 29049875],
      version: @genesis_block_version,
      difficulty_target: 1
    }
  end

  @spec genesis_block() :: block()
  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: []}
  end
end
