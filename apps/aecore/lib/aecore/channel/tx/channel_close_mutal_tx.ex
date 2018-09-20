defmodule Aecore.Channel.Tx.ChannelCloseMutalTx do
  @moduledoc """
  Module defining the ChannelCloseMutual transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Channel.ChannelStateTree
  alias Aecore.Channel.Tx.ChannelCloseMutalTx

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCloseMutal Transaction"
  @type payload :: %{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responser_amount: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelMutalClose Transaction type"
  @type t :: %ChannelCloseMutalTx{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer()
        }

  @doc """
  Definition of the ChannelCloseMutalTx structure

  # Parameters
  - channel_id: channel id
  - initiator_amount: the amount that the first sender commits
  - responder_amount: the amount that the second sender commits
  """
  defstruct [:channel_id, :initiator_amount, :responder_amount]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCloseMutalTx.t()
  def init(%{
        channel_id: channel_id,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    %ChannelCloseMutalTx{
      channel_id: channel_id,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCloseMutalTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ChannelCloseMutalTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{} = data_tx
      ) do
    senders = DataTx.senders(data_tx)

    cond do
      initiator_amount + responder_amount < 0 ->
        {:error, "#{__MODULE__}: Channel cannot have negative total balance"}

      length(senders) != 2 ->
        {:error, "#{__MODULE__}: Invalid from_accs size"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and closes channel (drops the channel object from chainstate)
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseMutalTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCloseMutalTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{} = data_tx
      ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, initiator_amount)
      end)
      |> AccountStateTree.update(responder_pubkey, fn acc ->
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
          ChannelCloseMutalTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        _accounts,
        channels,
        _block_height,
        %ChannelCloseMutalTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{fee: fee}
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      initiator_amount < 0 ->
        {:error, "#{__MODULE__}: Negative initiator balance"}

      responder_amount < 0 ->
        {:error, "#{__MODULE__}: Negative responder balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      channel.initiator_amount + channel.responder_amount !=
          initiator_amount + responder_amount + fee ->
        {:error, "#{__MODULE__}: Wrong total balance"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, _block_height, _tx, _data_tx, _fee) do
    # Fee is deducted from channel
    accounts
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(%SignedTx{data: %DataTx{fee: fee}}) do
    fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(ChannelCloseMutalTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %ChannelCloseMutalTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{senders: senders, nonce: nonce, fee: fee, ttl: ttl}
      ) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_list_to_binary(senders),
      :binary.encode_unsigned(nonce),
      channel_id,
      :binary.encode_unsigned(initiator_amount),
      :binary.encode_unsigned(responder_amount),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_senders,
        nonce,
        channel_id,
        initiator_amount,
        responder_amount,
        fee,
        ttl
      ]) do
    payload = %ChannelCloseMutalTx{
      channel_id: channel_id,
      initiator_amount: :binary.decode_unsigned(initiator_amount),
      responder_amount: :binary.decode_unsigned(responder_amount)
    }

    DataTx.init_binary(
      ChannelCloseMutalTx,
      payload,
      encoded_senders,
      :binary.decode_unsigned(fee),
      :binary.decode_unsigned(nonce),
      :binary.decode_unsigned(ttl)
    )
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
