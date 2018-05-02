defmodule Aecore.Chain.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx

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

  @spec rlp_encode(Block.t()) :: binary() | {:error, String.t()}
  def rlp_encode(%Block{} = block) do
    header_bin = Header.header_to_binary(block.header)

    txs =
      for tx <- block.txs do
        SignedTx.rlp_encode(tx)
      end

    [
      type_to_tag(Block),
      block.header.version,
      header_bin,
      txs
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(_) do
    {:error, "Invalid block or header struct"}
  end

  @spec rlp_decode(binary()) :: Block.t() | {:error, String.t()}
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      Block ->
        [header_bin, txs] = rest_data

        txs_list =
          for tx <- txs do
            DataTx.rlp_decode(tx)
          end

        Block.new(%{header: Header.binary_to_header(header_bin), txs: txs_list})

      _ ->
        {:error, "Invalid block serialization"}
    end
  end

  def rlp_decode(_) do
    {:error, "Illegal block serialization"}
  end

  defp type_to_tag(Block) do
    100
  end

  defp tag_to_type(100) do
    Block
  end
end
