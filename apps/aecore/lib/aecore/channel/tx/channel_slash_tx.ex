defmodule Aecore.Channel.Tx.ChannelSlashTx do
  @moduledoc """
  Aecore structure of ChannelSlashTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateOffChain, ChannelStateTree}

  require Logger

  @typedoc "Expected structure for the ChannelSlash Transaction"
  @type payload :: %{
          state: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

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
    %ChannelSlashTx{state: ChannelStateOffChain.init(state)}
  end

  @spec create(ChannelStateOffChain.t()) :: ChannelSlashTx.t()
  def create(state) do
    %ChannelSlashTx{state: state}
  end

  @spec sequence(ChannelSlashTx.t()) :: non_neg_integer()
  def sequence(%ChannelSlashTx{state: state}) do
    ChannelStateOffChain.sequence(state)
  end

  @spec channel_id(ChannelSlashTx.t()) :: binary()
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
        {:error, "#{__MODULE__}: Invalid senders size"}

      ChannelStateOffChain.sequence(state) == 0 ->
        {:error, "#{__MODULE__}: Can't slash with zero state"}

      true ->
        :ok
    end
  end

  @doc """
  Slashes channel.
  """
  @spec process_chainstate(
          ChainState.account(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: {:ok, {ChainState.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelSlashTx{state: state},
        _data_tx
      ) do
    channel_id = ChannelStateOffChain.id(state)

    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_slashing(channel, block_height, state)
      end)

    {:ok, {accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the ChannelSlashTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateTree.t(),
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
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't slash active channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, state)
    end
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          ChannelSlashTx.t(),
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
