defmodule Aecore.Block.Blocks do
  @moduledoc """
  This module is handling all operation
  in the blocks context

  TODO:
    - Implement block validation
    - Consider from where we will get the difficulty for a new block
    - Consider from where we will get the version for a new block
    - Provide some ExUnit tests
  """
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx

  @current_block_version 1

  @spec header(Block.block()) :: Header.header()
  def header(%Block{header: header}) do
    header
  end

  @spec set_header(Block.block(), Header.header()) :: Block.block()
  def set_header(%Block{}=block,%Header{}=header) do
    %{block | header: header}
  end

  @spec txs(Block.block()) :: list()
  def txs(%Block{txs: txs}) do
    txs
  end

  @spec set_txs(Block.block(), list()) :: Block.block()
  def set_txs(%Block{}=block, txs) do
    %{block | txs: txs}
  end

  @spec new(Block.block(), txs :: list())
  :: {:ok, Block.block()} | {:error, term()}
  def new(new_header, txs) do
    {:ok, %{Block.create | header: new_header, txs: txs}}
  end

end
