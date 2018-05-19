defmodule Aecore.Channel.Tx.ChannelSlashTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStateOffChain

  require Logger

  @typedoc "Expected structure for the ChannelSlash Transaction"
  @type payload :: %{
          state: ChannelStateOffChain.t()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the ChannelSlash Transaction type"
  @type t :: %ChannelSlashTx{
          state: ChannelStateOffChain.t()
        }

  @doc """
  Definition of Aecore ChannelSlashTx structure

  ## Parameters
  - state - the state to slash with
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{state: state} = _payload) do
    %ChannelSlashTx{state: state}
  end

  def create(state) do
    %ChannelSlashTx{state: state}
  end

  def sequence(%ChannelSlashTx{state: state}) do
    ChannelStateOffChain.sequence(state)
  end

  def channel_id(%ChannelSlashTx{state: state}) do
    ChannelStateOffChain.id(state)
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSlashTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSlashTx{state: state}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      length(senders) != 1 ->
        {:error, "Invalid senders size"}

      ChannelStateOffChain.sequence(state) == 0 ->
        {:error, "Can't slash with zero state"}

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
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelSlashTx{state: state},
        _data_tx
      ) do
    channel_id = ChannelStateOffChain.id(state)

    new_channels =
      Map.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_slashing(channel, block_height, state)
      end)

    {:ok, {accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelSlashTx{state: state},
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    channel_id = ChannelStateOffChain.id(state)
    channel = Map.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "Negative sender balance"}

      channel == nil ->
        {:error, "Channel doesn't exist (already closed?)"}

      ChannelStateOnChain.active?(channel) ->
        {:error, "Can't slash active channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, state)
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
end
