defmodule Aecore.Chain.MicroBlock do
  @moduledoc """
  Module defining the MicroBlock structure
  """
  alias Aecore.Chain.{MicroBlock, MicroHeader, KeyBlock, KeyHeader, BlockValidation, PoF}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Tx.SignedTx
  alias Aecore.Keys

  @type t :: %MicroBlock{
          header: MicroHeader.t(),
          txs: list(SignedTx.t()),
          proof_of_fraud: PoF.t()
        }

  defstruct [:header, :txs, :proof_of_fraud]

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
end
