defmodule Aecore.Channel.Tx.ChannelCreateTx do
  @moduledoc """
  Aecore structure of ChannelCreateTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  @behaviour Aecore.Channel.ChannelTransaction

  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree, ChannelOffchainUpdate}
  alias Aecore.Chain.Identifier
  alias Aecore.Channel.Updates.ChannelCreateUpdate

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCreateTx Transaction"
  @type payload :: %{
          initiator: binary(),
          initiator_amount: non_neg_integer(),
          responder: binary(),
          responder_amount: non_neg_integer(),
          locktime: non_neg_integer(),
          state_hash: binary(),
          channel_reserve: non_neg_integer(),
          channel_id: binary()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelCreate Transaction type"
  @type t :: %ChannelCreateTx{
          initiator: Identifier.t(),
          initiator_amount: non_neg_integer(),
          responder: Identifier.t(),
          responder_amount: non_neg_integer(),
          locktime: non_neg_integer(),
          state_hash: binary(),
          channel_reserve: non_neg_integer(),
          channel_id: Identifier.t(),
          sequence: non_neg_integer()
        }

  @doc """
  Definition of the ChannelCreateTx structure

  # Parameters
  - initiator: initiator of the channel creation
  - initiator_amount: the amount that the first sender commits
  - responder: responder of the channel creation
  - responder_amount: the amount that the second sender commits
  - locktime: number of blocks for dispute settling
  - state_hash: root hash of the initial offchain chainstate
  - channel_reserve: minimal ammount of tokens held by the initiator or responder
  - channel_id: id of the created channel - not sent to the blockchain but calculated here for convenience
  """
  defstruct [:initiator, :initiator_amount, :responder, :responder_amount, :locktime, :state_hash, :channel_reserve, :channel_id, sequence: 1]
  use ExConstructor

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCreateTx.t()
  def init(
        %{
          initiator: initiator,
          initiator_amount: initiator_amount,
          responder: responder,
          responder_amount: responder_amount,
          locktime: locktime,
          state_hash: state_hash,
          channel_reserve: channel_reserve,
          channel_id: channel_id
        } = _payload
      ) do
    %ChannelCreateTx{
      initiator: Identifier.create_identity(initiator, :account),
      initiator_amount: initiator_amount,
      responder: Identifier.create_identity(responder, :account),
      responder_amount: responder_amount,
      locktime: locktime,
      state_hash: state_hash,
      channel_reserve: channel_reserve,
      channel_id: Identifier.create_identity(channel_id, :channel)
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCreateTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%ChannelCreateTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      tx.initiator_amount + tx.responder_amount < 0 ->
        {:error, "#{__MODULE__}: Channel cannot have negative total balance"}

      tx.locktime < 0 ->
        {:error, "#{__MODULE__}: Locktime cannot be negative"}

      length(senders) != 2 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      tx.initiator_amount < tx.channel_reserve ->
        {:error, "#{__MODULE__}: Initiator amount does not meet minimal deposit"}

      tx.responder_amount < tx.channel_reserve ->
        {:error, "#{__MODULE__}: Responder amount does not meet minimal deposit"}

      byte_size(tx.state_hash) != 32 ->
        {:error, "#{__MODULE__}: Invalid state hash"}

      #Should we recreate the offchain chainstate and make sure that the state hash is correct?

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
        tx.locktime,
        tx.channel_reserve,
        tx.state_hash
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
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(ChannelCreateTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelCreateTx{} = tx, %DataTx{} = datatx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(tx.initiator),
      :binary.encode_unsigned(tx.initiator_amount),
      Identifier.encode_to_binary(tx.responder),
      :binary.encode_unsigned(tx.responder_amount),
      :binary.encode_unsigned(tx.channel_reserve),
      :binary.encode_unsigned(tx.locktime),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.fee),
      tx.state_hash,
      :binary.encode_unsigned(datatx.nonce)
    ]
  end

  defp decode_account_identifier_to_binary(encoded_identifier) do
  {:ok, %Identifier{type: :account, value: value}} = Identifier.decode_from_binary(encoded_identifier)
    value
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_initiator,
        initiator_amount,
        encoded_responder,
        responder_amount,
        channel_reserve,
        locktime,
        ttl,
        fee,
        state_hash,
        encoded_nonce
      ]) do
    initiator = decode_account_identifier_to_binary(encoded_initiator)
    responder = decode_account_identifier_to_binary(encoded_responder)
    nonce = :binary.decode_unsigned(encoded_nonce)
    payload = %ChannelCreateTx{
      initiator: initiator,
      initiator_amount: :binary.decode_unsigned(initiator_amount),
      responder: responder,
      responder_amount: :binary.decode_unsigned(responder_amount),
      channel_reserve: :binary.decode_unsigned(channel_reserve),
      locktime: :binary.decode_unsigned(locktime),
      state_hash: state_hash,
      channel_id: ChannelStateOnChain.id(initiator, responder, nonce)
    }

    DataTx.init_binary(
      ChannelCreateTx,
      payload,
      [encoded_initiator, encoded_responder],
      :binary.decode_unsigned(fee),
      nonce,
      :binary.decode_unsigned(ttl)
    )
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
  @spec offchain_updates(ChannelCreateTx.t()) :: list(ChannelOffchainUpdate.update_types())
  def offchain_updates(%ChannelCreateTx{} = tx) do
    [ChannelCreateUpdate.new(tx)]
  end
end
