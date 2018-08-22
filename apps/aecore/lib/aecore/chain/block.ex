defmodule Aecore.Chain.Block do
  @moduledoc """
  Structure of the block
  """

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
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

  # @spec genesis_header() :: Header.t()
  # defp genesis_header do
  #   header = Application.get_env(:aecore, :pow)[:genesis_header]
  #   struct(Header, header)
  # end

  def genesis_header do
    Header.new(%{
      height: 0,
      prev_hash:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>,
      txs_hash:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>,
      root_hash:
        <<232, 183, 193, 178, 72, 97, 49, 126, 122, 247, 245, 45, 43, 120, 61, 35, 210, 166, 103,
          167, 99, 167, 85, 205, 205, 254, 50, 201, 221, 174, 64, 108>>,
      target: 553_713_663,
      nonce: 0,
      time: 0,
      miner:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>,
      version: 15,
      pow_evidence: :no_value
    })
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
      :binary.encode_unsigned(block.header.version),
      Header.encode_to_binary(block.header),
      txs
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
