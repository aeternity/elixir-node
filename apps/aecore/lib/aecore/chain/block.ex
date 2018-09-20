defmodule Aecore.Chain.Block do
  @moduledoc """
  Module defining the Block structure
  """

  alias Aecore.Chain.{Block, Header}
  alias Aecore.Tx.SignedTx
  alias Aeutil.Serialization

  @version 15

  @typedoc "Structure of the Block Transaction type"
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

  @spec encode_to_map(Block.t()) :: map()
  def encode_to_map(%Block{header: header, txs: txs}) do
    serialized_header = Serialization.serialize_value(header)
    serialized_txs = Enum.map(txs, fn tx -> SignedTx.serialize(tx) end)
    Map.put(serialized_header, "transactions", serialized_txs)
  end

  @spec decode_from_map(map()) :: Block.t()
  def decode_from_map(%{"transactions" => txs} = block) do
    txs = Enum.map(txs, fn tx -> SignedTx.deserialize(tx) end)

    built_header =
      block
      |> Map.delete("transactions")
      |> Serialization.deserialize_value()
      |> Header.new()

    Block.new(header: built_header, txs: txs)
  end

  @spec encode_to_list(Block.t()) :: list()
  def encode_to_list(%Block{header: %Header{version: version} = header, txs: txs}) do
    encoded_txs =
      for tx <- txs do
        SignedTx.rlp_encode(tx)
      end

    [
      :binary.encode_unsigned(version),
      Header.encode_to_binary(header),
      encoded_txs
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Block.t()} | {:error, String.t()}
  def decode_from_list(@version, [header_bin, txs]) when is_list(txs) do
    with {:ok, txs_list} <- decode_txs_list(txs),
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

  defp decode_txs_list(list) do
    decode_txs_list(list, [])
  end

  defp decode_txs_list([], acc) do
    {:ok, acc}
  end

  defp decode_txs_list([encoded_tx | rest_encoded_txs], acc) do
    case SignedTx.rlp_decode(encoded_tx) do
      {:ok, tx} ->
        decode_txs_list(rest_encoded_txs, [tx | acc])

      {:error, _} = error ->
        error
    end
  end
end
