defmodule Aecore.Channel.Tx.ChannelCreateTx do
  @moduledoc """
  Aecore structure of ChannelCreateTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  @behaviour Aeutil.Serializable

  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree}
  alias Aeutil.Serialization

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
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t()
        ) :: {:ok, {ChainState.accounts(), ChannelStateTree.t()}}
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

    new_channels = ChannelStateTree.put(channels, channel_id, channel)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the ChannelCreateTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateTree.t(),
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

  def encode_to_list(%ChannelCreateTx{} = tx, %DataTx{} = datatx) do
    [
      @version,
      datatx.senders,
      datatx.nonce,
      tx.initiator_amount,
      tx.responder_amount,
      tx.locktime,
      datatx.fee,
      datatx.ttl
    ]
  end

  def decode_from_list(@version, [
        senders,
        nonce,
        initiator_amount,
        responder_amount,
        locktime,
        fee,
        ttl
      ]) do
    payload = %ChannelCreateTx{
      initiator_amount: Serialization.transform_item(initiator_amount, :int),
      responder_amount: Serialization.transform_item(responder_amount, :int),
      locktime: Serialization.transform_item(locktime, :int)
    }

    {:ok,
     DataTx.init(
       ChannelCreateTx,
       payload,
       senders,
       Serialization.transform_item(fee, :int),
       Serialization.transform_item(nonce, :int),
       Serialization.transform_item(ttl, :int)
     )}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
