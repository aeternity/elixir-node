defmodule Aecore.Chain.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aeutil.Serialization

  @type t :: %Block{
          header: Header.t(),
          txs: list(SignedTx.t())
        }

  @current_block_version 1

  defstruct [:header, :txs]
  use ExConstructor

  @spec current_block_version() :: non_neg_integer()
  def current_block_version do
    @current_block_version
  end

  @spec genesis_header() :: Header.t()
  defp genesis_header do
    header = Application.get_env(:aecore, :pow)[:genesis_header]
    struct(Header, header)
  end

  @spec genesis_block() :: Block.t()
  def genesis_block do
    header = genesis_header()
    %Block{header: header, txs: []}
  end

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), Block.t()) ::
          binary() | {:error, String.t()}
  def rlp_encode(tag, _vsn, %Block{} = block) do
    header_bin = Header.header_to_binary(block.header)

    txs =
      for tx <- block.txs do
        Serialization.rlp_encode(tx, :signedtx)
      end

    [
      tag,
      block.header.version,
      header_bin,
      txs
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(_) do
    {:error, "Invalid block or header struct"}
  end

  @spec rlp_decode(list()) :: Block.t() | {:error, String.t()}
  def rlp_decode([header_bin, txs]) do
    txs_list =
      for tx <- txs do
        Serialization.rlp_decode(tx)
      end

    Block.new(%{header: Header.binary_to_header(header_bin), txs: txs_list})
  end

  def rlp_decode(_) do
    {:error, "#{__MODULE__} : Illegal block serialization"}
  end
end
