defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @type t :: %Block{}

  @current_block_version 1
  @genesis_block_version @current_block_version

  defstruct [:header, :txs]
  use ExConstructor

  @spec current_block_version() :: integer
  def current_block_version() do
    @current_block_version
  end

  defp genesis_header() do
    h = Application.get_env(:aecore, :pow)[:genesis_header]
    struct(Header, h)
  end

  @spec genesis_block() :: Block.t
  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: []}
  end
end
