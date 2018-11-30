defmodule Aecore.Chain.MicroBlock do
  @moduledoc """
  Module defining the MicroBlock structure
  """
  alias Aecore.Chain.{MicroBlock, MicroHeader, KeyBlock, KeyHeader, BlockValidation}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Tx.SignedTx
  alias Aecore.Keys

  @rlp_tag 101
  @header_version 1
  @header_tag 0
  @header_min_bytes 216
  @type t :: %MicroBlock{
          header: MicroHeader.t(),
          txs: list(SignedTx.t())
          # pof: :no_fraud  TODO: implement PoF
        }

  defstruct [:header, :txs]

  @spec validate(MicroBlock.t(), KeyBlock.t() | MicroBlock.t()) :: :ok | {:error, String.t()}
  def validate(
        %MicroBlock{
          header: %MicroHeader{time: new_time, signature: signature, txs_hash: txs_hash} = header,
          txs: txs
        },
        %{
          header: %{time: prev_block_time, prev_key_hash: prev_key_hash} = prev_header
        } = prev_block
      ) do
    prev_key_block =
      case prev_block do
        %KeyBlock{} ->
          prev_block

        %MicroBlock{} ->
          {:ok, key_block} = Chain.get_block(prev_key_hash)
          key_block
      end

    # header was signed with this signature in mining
    header_with_zero_signature = %{header | signature: <<0::512>>}

    is_signature_valid =
      header_with_zero_signature
      |> MicroHeader.encode_to_binary()
      |> Keys.verify(signature, prev_key_block.header.miner)

    is_minimum_distance_met =
      case prev_header do
        %KeyHeader{} ->
          new_time > prev_block_time

        %MicroHeader{} ->
          new_time >= prev_block_time + GovernanceConstants.micro_block_distance()
      end

    cond do
      !is_minimum_distance_met ->
        {:error, "#{__MODULE__}: Micro block too close to previous block"}

      !is_signature_valid ->
        {:error, "#{__MODULE__}: Invalid micro block signature"}

      txs_hash != BlockValidation.calculate_txs_hash(txs) ->
        {:error, "#{__MODULE__}: Root hash of transactions does not match the one in header"}

      true ->
        :ok
    end
  end

  @spec encode_to_binary(MicroBlock.t()) :: binary()
  def encode_to_binary(%MicroBlock{header: header, txs: txs}) do
    encoded_header = MicroHeader.encode_to_binary(header)

    encoded_txs =
      for tx <- txs do
        SignedTx.rlp_encode(tx)
      end

    # TODO implement PoF serializations
    encoded_pof = <<>>
    encoded_rest_data = ExRLP.encode([@rlp_tag, header.version, encoded_txs, encoded_pof])
    <<encoded_header::binary, encoded_rest_data::binary>>
  end

  @spec decode_from_binary(binary()) :: {:ok, MicroBlock.t()} | {:error, String.t()}
  def decode_from_binary(binary) when is_binary(binary) do
    case partial_decode(binary) do
      {:error, reason} -> {:error, "#{__MODULE__}: #{inspect(reason)}"}
      {header, rest_data} -> decode_micro_block(rest_data, header)
    end
  end

  defp partial_decode(<<@header_version::32, @header_tag::8, _::binary>> = binary) do
    # TODO When PoF is implemented, this should be adjusted
    header_size = @header_min_bytes

    case binary do
      <<header_bin::binary-size(header_size), rest::binary>> ->
        case MicroHeader.decode_from_binary(header_bin) do
          {:ok, header} -> {header, rest}
          _ -> {:error, "#{__MODULE__}: Malformed header for #{__MODULE__} struct"}
        end

      _ ->
        {:error, "#{__MODULE__}: Invalid micro header size"}
    end
  end

  defp partial_decode(_) do
    {:error, "#{__MODULE__}: Illegal serialization"}
  end

  defp decode_micro_block(rest_data, %MicroHeader{version: @header_version} = header) do
    [_tag, _vsn, encoded_txs, _encoded_pof] = ExRLP.decode(rest_data)

    decoded_txs_list =
      for encoded_tx <- encoded_txs do
        SignedTx.rlp_decode(encoded_tx)
      end

    # TODO implement PoF deserializations
    # decoded_pof=  <<>>
    {:ok, %MicroBlock{header: header, txs: decoded_txs_list}}
  end

  defp decode_micro_block(_rest_data, _header) do
    {:error, "#{__MODULE__} Unknown micro block data"}
  end
end
