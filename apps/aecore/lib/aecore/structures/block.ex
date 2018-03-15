defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx

  @type t :: %Block{
    header: Header.t,
    txs: list(SignedTx.t())
  }

  @current_block_version 1

  defstruct [:header, :txs]
  use ExConstructor

  @spec current_block_version() :: non_neg_integer()
  def current_block_version() do
    @current_block_version
  end

  @spec genesis_header() :: Header.t
  defp genesis_header() do
    h = Application.get_env(:aecore, :pow)[:genesis_header]
    struct(Header, h)
  end

  @spec genesis_block() :: Block.t()
  def genesis_block() do
    h = genesis_header()
    %Block{header: h, txs: []}
  end
end
