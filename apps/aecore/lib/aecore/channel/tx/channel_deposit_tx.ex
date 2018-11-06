defmodule Aecore.Channel.Tx.ChannelDepositTx do
  @moduledoc """
  Aecore structure of ChannelDepositTx transaction data.
  """

  use Aecore.Tx.Transaction
  @behaviour Aecore.Channel.ChannelTransaction

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Channel.Tx.ChannelDepositTx
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree, ChannelOffChainUpdate}
  alias Aecore.Chain.{Identifier, Chainstate}
  alias Aecore.Channel.Updates.ChannelDepositUpdate

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelDepositTx Transaction"
  @type payload :: %{
          channel_id: binary(),
          depositing_account: binary(),
          amount: non_neg_integer(),
          state_hash: binary(),
          sequence: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelDeposit Transaction type"
  @type t :: %ChannelDepositTx{
          channel_id: binary(),
          depositing_account: binary(),
          amount: non_neg_integer(),
          state_hash: binary(),
          sequence: non_neg_integer()
        }

  @doc """
  Definition of the ChannelDepositTx structure

  # Parameters
  - channel_id: id of the channel for which the transaction is meant
  - depositing_account: the depositing account
  - amount: the amount of tokens deposited into the channel
  - state_hash: root hash of the offchain chainstate after applying this transaction to it
  - sequence: sequence of the channel after applying this transaction to the channel
  """
  defstruct [
    :channel_id,
    :depositing_account,
    :amount,
    :state_hash,
    :sequence
  ]

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  def chainstate_senders?(), do: true

  @doc """
  One of the senders in ChannelDepositTx is not passed with tx, but is supposed to be retrieved from Chainstate. The senders have to be channel initiator and responder.
  """
  @spec senders_from_chainstate(ChannelDepositTx.t(), Chainstate.t()) :: list(binary())
  def senders_from_chainstate(
        %ChannelDepositTx{channel_id: channel_id, depositing_account: depositing_account},
        chainstate
      ) do
    with %ChannelStateOnChain{
           initiator_pubkey: initiator_pubkey,
           responder_pubkey: responder_pubkey
         } <- ChannelStateTree.get(chainstate.channels, channel_id),
         [second_party] <- [initiator_pubkey, responder_pubkey] -- [depositing_account] do
      [depositing_account, second_party]
    else
      v when v === :none or is_list(v) ->
        []
    end
  end

  @spec init(payload()) :: ChannelDepositTx.t()
  def init(%{
        channel_id: channel_id,
        depositing_account: depositing_account,
        amount: amount,
        state_hash: state_hash,
        sequence: sequence
      }) do
    %ChannelDepositTx{
      channel_id: channel_id,
      depositing_account: depositing_account,
      amount: amount,
      state_hash: state_hash,
      sequence: sequence
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelDepositTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ChannelDepositTx{
          channel_id: channel_id,
          amount: amount,
          state_hash: state_hash,
          sequence: sequence
        },
        _data_tx
      ) do
    cond do
      byte_size(channel_id) != 32 ->
        {:error, "#{__MODULE__}: Invalid channel id"}

      amount < 0 ->
        {:error, "#{__MODULE__}: Can't deposit negative amount of tokens"}

      byte_size(state_hash) != 32 ->
        {:error, "#{__MODULE__}: Invalid state hash"}

      sequence < 0 ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      true ->
        :ok
    end
  end

  @doc """
  Deposits tokens from the channel
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelDepositTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}} | no_return()
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelDepositTx{
          channel_id: channel_id,
          depositing_account: depositing_account,
          amount: amount,
          state_hash: state_hash,
          sequence: sequence
        },
        _data_tx,
        _context
      ) do
    new_accounts =
      AccountStateTree.update(accounts, depositing_account, fn account ->
        Account.apply_transfer!(account, block_height, amount * -1)
      end)

    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_deposit(
          channel,
          amount,
          sequence,
          state_hash
        )
      end)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelDepositTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelDepositTx{
          channel_id: channel_id,
          depositing_account: depositing_account,
          amount: amount,
          sequence: sequence
        },
        %DataTx{
          fee: fee
        },
        _context
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    depositing_account_balance =
      AccountStateTree.get(accounts, depositing_account).balance - fee - amount

    cond do
      AccountStateTree.get(accounts, depositing_account).balance - fee - amount < 0 ->
        {:error,
         "#{__MODULE__}: Negative balance of the depositing account(#{depositing_account_balance})"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel does not exists"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't deposit from inactive channel."}

      true ->
        ChannelStateOnChain.validate_deposit(channel, depositing_account, amount, sequence)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelDepositTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(
        accounts,
        block_height,
        %ChannelDepositTx{depositing_account: depositing_account},
        _data_tx,
        fee
      ) do
    AccountStateTree.update(accounts, depositing_account, fn acc ->
      Account.apply_transfer!(acc, block_height, fee * -1)
    end)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelDepositTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %ChannelDepositTx{
          channel_id: channel_id,
          depositing_account: depositing_account,
          amount: amount,
          state_hash: state_hash,
          sequence: sequence
        },
        data_tx
      ) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(channel_id, :channel),
      Identifier.create_encoded_to_binary(depositing_account, :account),
      :binary.encode_unsigned(amount),
      :binary.encode_unsigned(data_tx.ttl),
      :binary.encode_unsigned(data_tx.fee),
      state_hash,
      :binary.encode_unsigned(sequence),
      :binary.encode_unsigned(data_tx.nonce)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_channel_id,
        encoded_depositing_account,
        amount,
        ttl,
        fee,
        state_hash,
        sequence,
        nonce
      ])
      when is_binary(state_hash) do
    with {:ok, channel_id} <-
           Identifier.decode_from_binary_to_value(encoded_channel_id, :channel),
         {:ok, depositing_account} <-
           Identifier.decode_from_binary_to_value(encoded_depositing_account, :account) do
      payload = %{
        channel_id: channel_id,
        depositing_account: depositing_account,
        amount: :binary.decode_unsigned(amount),
        state_hash: state_hash,
        sequence: :binary.decode_unsigned(sequence)
      }

      DataTx.init_binary(
        ChannelDepositTx,
        payload,
        [],
        :binary.decode_unsigned(fee),
        :binary.decode_unsigned(nonce),
        :binary.decode_unsigned(ttl)
      )
    else
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

  @doc """
    Get a list of offchain updates to the offchain chainstate
  """
  @spec offchain_updates(SignedTx.t() | DataTx.t()) :: list(ChannelOffChainUpdate.update_types())
  def offchain_updates(%SignedTx{data: data}) do
    offchain_updates(data)
  end

  def offchain_updates(%DataTx{
        type: ChannelDepositTx,
        payload: tx
      }) do
    [ChannelDepositUpdate.new(tx)]
  end
end
