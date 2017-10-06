defmodule Aecore.Block.Genesis do
  @moduledoc """
  Genesis Block
  """

  alias Aecore.Structures.Header
  alias Aecore.Structures.Block

  def genesis_header() do
    %{Header.create
      | height: 0,
        prev_hash: <<0::256>>,
        txs_hash: <<0::256>>,
        timestamp: 1507275094308,
        nonce: 19,
        version: 1,
        difficulty_target: 1}
  end

  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: [] }
  end

end
