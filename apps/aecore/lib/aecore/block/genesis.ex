defmodule Aecore.Block.Genesis do
  @moduledoc """
  Genesis Block
  """

  alias Aecore.Structures.Header
  alias Aecore.Structures.Block

  def genesis_header() do
    Aecore.Block.Headers.new(0,<<0::size(256)>>,<<0::size(256)>>,1,0,1)
  end

  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: [] }
  end

end
