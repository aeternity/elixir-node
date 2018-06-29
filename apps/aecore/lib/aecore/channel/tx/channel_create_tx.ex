defmodule Aecore.Channel.Tx.ChannelCreateTx do
  @moduledoc """
  Aecore structure of ChannelCreateTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.Worker, as: Channel

  require Logger

  @typedoc "Expected structure for the ChannelCreateTx Transaction"
  @type payload :: %{
          initiator_amount: non_neg_integer(),
          responser_amount: non_neg_integer(),
          locktime: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Channel.channels_onchain()

  @typedoc "Structure of the ChannelCreate Transaction type"
  @type t :: %ChannelCreateTx{
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer(),
          locktime: non_neg_integer()
        }

  @doc """
  Definition of Aecore ChannelCreateTx structure

  ## Parameters
  - initiator_amount: amount that account first on the senders list commits
  - responser_amount: amount that account second on the senders list commits
  - locktime: number of blocks for dispute settling
  """
  defstruct [:initiator_amount, :responder_amount, :locktime]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCreateTx.t()
  def init(
        %{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          locktime: locktime
        } = _payload
      ) do
    %ChannelCreateTx{
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      locktime: locktime
    }
  end

  @spec initiator_amount(ChannelCreateTx.t()) :: non_neg_integer()
  def initiator_amount(%ChannelCreateTx{initiator_amount: initiator_amount}) do
    initiator_amount
  end

  @spec responder_amount(ChannelCreateTx.t()) :: non_neg_integer()
  def responder_amount(%ChannelCreateTx{responder_amount: responder_amount}) do
    responder_amount
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelCreateTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelCreateTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      tx.initiator_amount + tx.responder_amount < 0 ->
        {:error, "#{__MODULE__}: Channel cannot have negative total balance"}

      tx.locktime < 0 ->
        {:error, "#{__MODULE__}: Locktime cannot be negative"}

      length(senders) != 2 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

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
          ChannelCreateTx.t(),
          DataTx.t()
        ) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCreateTx{} = tx,
        data_tx
      ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    nonce = DataTx.nonce(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.initiator_amount * -1)
      end)
      |> AccountStateTree.update(responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.responder_amount * -1)
      end)

    channel =
      ChannelStateOnChain.create(
        initiator_pubkey,
        responder_pubkey,
        tx.initiator_amount,
        tx.responder_amount,
        tx.locktime
      )

    channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    new_channels = Map.put(channels, channel_id, channel)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the ChannelCreateTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCreateTx{} = tx,
        data_tx
      ) do
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    nonce = DataTx.nonce(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, initiator_pubkey).balance - (fee + tx.initiator_amount) < 0 ->
        {:error, "#{__MODULE__}: Negative initiator balance"}

      AccountStateTree.get(accounts, responder_pubkey).balance - tx.responder_amount < 0 ->
        {:error, "#{__MODULE__}: Negative responder balance"}

      Map.has_key?(channels, ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)) ->
        {:error, "#{__MODULE__}: Channel already exists"}

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
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end
end
