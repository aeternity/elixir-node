defmodule Aecore.Channel.Tx.ChannelCloseMutalTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelCloseMutalTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain

  require Logger

  @typedoc "Expected structure for the ChannelCloseMutal Transaction"
  @type payload :: %{
    channel_id: binary(),
    initiator_amount: non_neg_integer(),
    responser_amount: non_neg_integer()
  }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the ChannelMutalClose Transaction type"
  @type t :: %ChannelCloseMutalTx{
    channel_id: binary(),
    initiator_amount: non_neg_integer(),
    responder_amount: non_neg_integer()
  }

  @doc """
  Definition of Aecore ChannelCreateTx structure

  ## Parameters
  - channel_id: channel id
  - initiator_amount: amount that account first on the senders list commits
  - responser_amount: amount that account second on the senders list commits
  """
  defstruct [:channel_id, :initiator_amount, :responder_amount]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{channel_id: channel_id, initiator_amount: initiator_amount, responder_amount: responder_amount} = _payload) do
    %ChannelCloseMutalTx{channel_id: channel_id,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount}
  end

  def channel_id(%ChannelCloseMutalTx{channel_id: channel_id}) do channel_id end 
  
  def initiator_amount(%ChannelCloseMutalTx{initiator_amount: initiator_amount}) do initiator_amount end

  def responder_amount(%ChannelCloseMutalTx{responder_amount: responder_amount}) do responder_amount end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelCloseMutalTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelCloseMutalTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)
    
    cond do
      tx.initiator_amount + tx.responder_amount < 0 ->
        {:error, "Channel cannot have negative total balance"}

      length(senders) != 2 ->
        {:error, "Invalid from_accs size"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and creates channel object
  """
  @spec process_chainstate(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelCloseMutalTx.t(),
          DataTx.t()) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
    accounts,
    channels,
    block_height,
    %ChannelCloseMutalTx{channel_id: channel_id} = tx,
    data_tx
  ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.initiator_amount)
      end)
      |> AccountStateTree.update(responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.responder_amount)
      end)

    new_channels = Map.drop(channels, [channel_id])

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
    %ChannelCloseMutalTx{} = tx,
    data_tx
  ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    fee = DataTx.fee(data_tx)
    channel = Map.get(channels, tx.channel_id)

    cond do
      AccountStateTree.get(accounts, initiator_pubkey).balance - ((fee+1)/2) + tx.initiator_amount < 0 ->
        {:error, "Negative initiator balance"}

      AccountStateTree.get(accounts, responder_pubkey).balance - (fee/2) + tx.responder_amount < 0 ->
        {:error, "Negative responder balance"}

      channel == nil ->
        {:error, "Channel doesn't exist (already closed?)"}

      channel.initiator_amount + channel.responder_amount != tx.initiator_amount + tx.responder_amount ->
        {:error, "Wrong total balance"}

      true ->
        :ok
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
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)

    accounts
    |> AccountStateTree.update(initiator_pubkey, fn acc ->
      Account.apply_transfer!(acc, block_height, -1 * div((fee + 1), 2))
    end)
    |> AccountStateTree.update(responder_pubkey, fn acc ->
      Account.apply_transfer!(acc, block_height, -1 * div(fee, 2))
    end)
  end

end
