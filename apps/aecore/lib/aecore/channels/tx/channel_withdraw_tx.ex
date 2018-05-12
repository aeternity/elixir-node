defmodule Aecore.Channel.Tx.ChannelWithdrawTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelWithdrawTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Wallet.Worker, as: Wallet 

  require Logger

  @typedoc "Expected structure for the ChannelWithdraw Transaction"
  @type payload :: %{
    channel_id: binary(),
    amount: non_neg_integer(),
    receiver: Wallet.pubkey(),
    party: :initiator | :receiver
  }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateOnChain.channels()

  @typedoc "Structure of the ChannelWithdraw Transaction type"
    channel_id: binary(),
    amount: non_neg_integer(),
    receiver: Wallet.pubkey(),
    party: :initiator | :receiver
  }

  @doc """
  Definition of Aecore ChannelWithdrawTx structure

  ## Parameters
  TODO
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{channel_id: channel_id, amount: amount, receiver: receiver} = _payload) do
    %ChannelWithdrawTx{channel_id: channel_id, amount: amount, receiver: receiver}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelWithdrawTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelWithdrawTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)
    
    cond do
      tx.amount < 0 ->
        {:error, "Cannot withdraw negative amount"}

      length(senders) != 2 ->
        {:error, "Invalid senders size"}

      tx.party != :initiator && tx.party != :receiver ->
        {:error, "Wrong party"}

      true ->
        :ok
    end
  end

  @doc """
  TODO
  """
  @spec process_chainstate(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelWithdrawTx.t(),
          DataTx.t()) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
    accounts,
    channels,
    block_height,
    %ChannelWithdrawTx{} = tx,
    data_tx
  ) do
    
    #ChannelOffChainState.validate

    new_channels = Map.update!(channels, tx.channel_id, fn channel ->
      ChannelStateOnChain.apply_withdraw(channel, tx.party, tx.amount)
    end)

    new_accounts = AccountStateTree.update(accounts, tx.receiver, fn acc ->
      Account.apply_transfer!(acc, block_height, tx.amount)
    end)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelCloseMutalTx.t(),
          DataTx.t()) 
  :: :ok
  def preprocess_check(
    accounts,
    channels,
    _block_height,
    %ChannelWithdrawTx{} = tx,
    data_tx
  ) do
    senders = DataTx.main_sender(data_tx)
    channel = Map.get(channels, tx.channel_id)

    cond do
      channel == nil ->
        {:error, "Channel doesn't exist (already closed?)"}

      senders != ChannelStateOnChain.pubkeys(channel) ->
        {:error, "Wrong senders"}

      true ->
        ChannelStateOnChain.validate_withdraw(channel, tx.party, tx.amount)
    end
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t(),
          non_neg_integer()
  ) :: ChainState.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
    #TODO proper fee deduction
  end

end
