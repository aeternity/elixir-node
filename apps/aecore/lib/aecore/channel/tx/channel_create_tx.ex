defmodule Aecore.Channel.Tx.ChannelCreateTx do
  @moduledoc """
  Module defining the ChannelCreate transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree}
  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Tx.DataTx

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCreateTx Transaction"
  @type payload :: %{
          initiator_amount: non_neg_integer(),
          responser_amount: non_neg_integer(),
          locktime: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelCreate Transaction type"
  @type t :: %ChannelCreateTx{
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer(),
          locktime: non_neg_integer()
        }

  @doc """
  Definition of the ChannelCreateTx structure

  # Parameters
  - initiator_amount: the amount that the first sender commits
  - responder_amount: the amount that the second sender commits
  - locktime: number of blocks for dispute settling
  """
  defstruct [:initiator_amount, :responder_amount, :locktime]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCreateTx.t()
  def init(%{
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        locktime: locktime
      }) do
    %ChannelCreateTx{
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      locktime: locktime
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCreateTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ChannelCreateTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          locktime: locktime
        },
        %DataTx{} = data_tx
      ) do
    senders = DataTx.senders(data_tx)

    cond do
      initiator_amount + responder_amount < 0 ->
        {:error, "#{__MODULE__}: Channel cannot have negative total balance"}

      locktime < 0 ->
        {:error, "#{__MODULE__}: Locktime cannot be negative"}

      length(senders) != 2 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and creates a channel object
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCreateTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          locktime: locktime
        },
        %DataTx{nonce: nonce} = data_tx
      ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, initiator_amount * -1)
      end)
      |> AccountStateTree.update(responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, responder_amount * -1)
      end)

    channel =
      ChannelStateOnChain.create(
        initiator_pubkey,
        responder_pubkey,
        initiator_amount,
        responder_amount,
        locktime
      )

    channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    new_channels = ChannelStateTree.put(channels, channel_id, channel)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCreateTx{initiator_amount: initiator_amount, responder_amount: responder_amount},
        %DataTx{nonce: nonce, fee: fee} = data_tx
      ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)

    cond do
      AccountStateTree.get(accounts, initiator_pubkey).balance - (fee + initiator_amount) < 0 ->
        {:error, "#{__MODULE__}: Negative initiator balance"}

      AccountStateTree.get(accounts, responder_pubkey).balance - responder_amount < 0 ->
        {:error, "#{__MODULE__}: Negative responder balance"}

      ChannelStateTree.has_key?(
        channels,
        ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
      ) ->
        {:error, "#{__MODULE__}: Channel already exists"}

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
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelCreateTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %ChannelCreateTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          locktime: locktime
        },
        %DataTx{senders: senders, nonce: nonce, fee: fee, ttl: ttl}
      ) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_list_to_binary(senders),
      :binary.encode_unsigned(nonce),
      :binary.encode_unsigned(initiator_amount),
      :binary.encode_unsigned(responder_amount),
      :binary.encode_unsigned(locktime),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_senders,
        nonce,
        initiator_amount,
        responder_amount,
        locktime,
        fee,
        ttl
      ]) do
    payload = %ChannelCreateTx{
      initiator_amount: :binary.decode_unsigned(initiator_amount),
      responder_amount: :binary.decode_unsigned(responder_amount),
      locktime: :binary.decode_unsigned(locktime)
    }

    DataTx.init_binary(
      ChannelCreateTx,
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
