defmodule Aecore.Channel.Tx.ChannelSettleTx do
  @moduledoc """
  Module defining the ChannelSettle transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelSettleTx
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree}
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSettle Transaction"
  @type payload :: %{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSettle Transaction type"
  @type t :: %ChannelSettleTx{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer()
        }

  @doc """
  Definition of the ChannelSettleTx structure

  # Parameters
  - channel_id: channel id
  """
  defstruct [:channel_id, :initiator_amount, :responder_amount]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCreateTx.t()
  def init(
        %{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        } = _payload
      ) do
    %ChannelSettleTx{
      channel_id: channel_id,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelSettleTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%ChannelSettleTx{}, %DataTx{senders: senders}) do
    if length(senders) != 1 do
      {:error, "#{__MODULE__}: Invalid from_accs size"}
    else
      :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and closes the channel (drops the channel object)
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelSettleTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        _data_tx
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    new_accounts =
      accounts
      |> AccountStateTree.update(channel.initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, initiator_amount)
      end)
      |> AccountStateTree.update(channel.responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, responder_amount)
      end)

    new_channels = ChannelStateTree.delete(channels, channel_id)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        block_height,
        %ChannelSettleTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]}
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance < fee ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.settled?(channel, block_height) ->
        {:error, "#{__MODULE__}: Channel isn't settled"}

      channel.initiator_amount != initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initiator amount"}

      channel.responder_amount != responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(%SignedTx{data: %DataTx{fee: fee}}) do
    fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(ChannelSettleTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelSettleTx{} = tx, %DataTx{senders: [sender]} = data_tx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(tx.channel_id, :channel),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(tx.initiator_amount),
      :binary.encode_unsigned(tx.responder_amount),
      :binary.encode_unsigned(data_tx.ttl),
      :binary.encode_unsigned(data_tx.fee),
      :binary.encode_unsigned(data_tx.nonce)
    ]
  end

  def decode_from_list(@version, [
        encoded_channel_id,
        encoded_sender,
        initiator_amount,
        responder_amount,
        ttl,
        fee,
        nonce
      ]) do
    case Identifier.decode_from_binary_to_value(encoded_channel_id, :channel) do
      {:ok, channel_id} ->
        payload = %ChannelSettleTx{
          channel_id: channel_id,
          initiator_amount: :binary.decode_unsigned(initiator_amount),
          responder_amount: :binary.decode_unsigned(responder_amount)
        }

        DataTx.init_binary(
          ChannelSettleTx,
          payload,
          [encoded_sender],
          :binary.decode_unsigned(fee),
          :binary.decode_unsigned(nonce),
          :binary.decode_unsigned(ttl)
        )

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
