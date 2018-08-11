defmodule Aecore.Chain.Block do
  @moduledoc """
  Structure of the block
  """

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.BlockValidation
  alias Aeutil.Serialization

  @version 14

  @type t :: %Block{
          header: Header.t(),
          txs: list(SignedTx.t())
        }

  defstruct [:header, :txs]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec current_block_version() :: non_neg_integer()
  def current_block_version do
    @version
  end

  @spec genesis_header() :: Header.t()
  defp genesis_header do
    header = Application.get_env(:aecore, :pow)[:genesis_header]
    struct(Header, header)
  end

  def genesis_hash do
    BlockValidation.block_header_hash(genesis_header())
  end

  @spec genesis_block() :: Block.t()
  def genesis_block do
    header = genesis_header()
    %Block{header: header, txs: []}
  end

  @spec encode_to_map(Block.t()) :: map()
  def encode_to_map(%Block{} = block) do
    serialized_header = Serialization.serialize_value(block.header)
    serialized_txs = Enum.map(block.txs, fn tx -> SignedTx.serialize(tx) end)

    Map.put(serialized_header, "transactions", serialized_txs)
  end

  @spec decode_from_map(map()) :: Block.t()
  def decode_from_map(%{} = block) do
    txs = Enum.map(block["transactions"], fn tx -> SignedTx.deserialize(tx) end)

    built_header =
      block
      |> Map.delete("transactions")
      |> Serialization.deserialize_value()
      |> Header.new()

    Block.new(header: built_header, txs: txs)
  end

  @spec encode_to_list(Block.t()) :: list()
  def encode_to_list(%Block{} = block) do
    txs =
      for tx <- block.txs do
        SignedTx.rlp_encode(tx)
      end

    [
      block.header.version,
      Header.encode_to_binary(block.header),
      txs
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Block.t()} | {:error, String.t()}
  def decode_from_list(@version, [header_bin, txs]) when is_list(txs) do
    txs_list =
      for tx <- txs do
        SignedTx.rlp_decode(tx)
      end

    with :ok <- txs_list_valid(txs_list),
         {:ok, header} <- Header.decode_from_binary(header_bin) do
      {:ok, %Block{header: header, txs: txs_list}}
    else
      {:error, _} = error -> error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end

  defp txs_list_valid([]) do
    :ok
  end

  defp txs_list_valid([tx | rest]) do
    case tx do
      %SignedTx{} ->
        txs_list_valid(rest)

      {:error, _} = error ->
        error
    end
  end
end
