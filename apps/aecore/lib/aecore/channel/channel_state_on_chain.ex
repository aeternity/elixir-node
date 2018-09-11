defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  Module defining the structure of the OnChain Channel state
  """

  require Logger

  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateOffChain}
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash
  alias Aecore.Keys
  alias Aeutil.Serialization

  @version 1

  @typedoc "Structure of the ChannelStateOnChain Transaction type"
  @type t :: %ChannelStateOnChain{
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          initiator_amount: integer(),
          responder_amount: integer(),
          lock_period: non_neg_integer(),
          slash_close: integer(),
          slash_sequence: integer()
        }

  @type id :: binary()

  @doc """
  Definition of the State Channel OnChain structure

  # Parameters
  - initiator_pubkey
  - responder_pubkey
  - initiator_amount - amount deposited by initiator or from slashing
  - responder_amount - amount deposited by responder or from slashing
  - lock_period - time before slashing is settled
  - slash_close - when != 0: block height when slashing is settled
  - slash_sequence - when != 0: sequence or slashing
  """
  defstruct [
    :initiator_pubkey,
    :responder_pubkey,
    :initiator_amount,
    :responder_amount,
    :lock_period,
    :slash_close,
    :slash_sequence
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(Keys.pubkey(), Keys.pubkey(), integer(), integer(), non_neg_integer()) ::
          ChannelStateOnChain.t()
  def create(initiator_pubkey, responder_pubkey, initiator_amount, responder_amount, lock_period) do
    %ChannelStateOnChain{
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      lock_period: lock_period,
      slash_close: 0,
      slash_sequence: 0
    }
  end

  @doc """
  Generates a channel id from a ChannelCreateTx.
  """
  @spec id(DataTx.t()) :: id()
  def id(data_tx) do
    nonce = DataTx.nonce(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id(initiator_pubkey, responder_pubkey, nonce)
  end

  @doc """
  Generates a channel id from detail of ChannelCreateTx.
  """
  @spec id(Keys.pubkey(), Keys.pubkey(), non_neg_integer()) :: id()
  def id(initiator_pubkey, responder_pubkey, nonce) do
    binary_data = initiator_pubkey <> <<nonce::size(64)>> <> responder_pubkey

    Hash.hash_blake2b(binary_data)
  end

  @spec amounts(ChannelStateOnChain.t()) :: {non_neg_integer(), non_neg_integer()}
  def amounts(%ChannelStateOnChain{
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    {initiator_amount, responder_amount}
  end

  @spec pubkeys(ChannelStateOnChain.t()) :: {Keys.pubkey(), Keys.pubkey()}
  def pubkeys(%ChannelStateOnChain{
        initiator_pubkey: initiator_pubkey,
        responder_pubkey: responder_pubkey
      }) do
    {initiator_pubkey, responder_pubkey}
  end

  @doc """
  Returns true if the channel wasn't slashed. (Closed channels should be removed from the Channels state tree)
  """
  @spec active?(ChannelStateOnChain.t()) :: boolean()
  def active?(%ChannelStateOnChain{slash_close: 0}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  @doc """
  Returns true if the Channel can be settled. (If the Channel has been slashed and the current block height exceeds the locktime)
  """
  @spec settled?(ChannelStateOnChain.t(), non_neg_integer()) :: boolean()
  def settled?(%ChannelStateOnChain{slash_close: slash_close} = channel, block_height) do
    block_height >= slash_close && !active?(channel)
  end

  @doc """
  Validates Slash and SoloCloseTx states.
  """
  @spec validate_slashing(ChannelStateOnChain.t(), ChannelStateOffChain.t()) ::
          :ok | {:error, binary()}
  def validate_slashing(
        %ChannelStateOnChain{} = channel,
        %ChannelStateOffChain{sequence: 0} = offchain_state
      ) do
    cond do
      channel.slash_sequence != 0 ->
        {:error, "#{__MODULE__}: Channel already slashed"}

      channel.initiator_amount != offchain_state.initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initator amount"}

      channel.responder_amount != offchain_state.responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      true ->
        :ok
    end
  end

  def validate_slashing(%ChannelStateOnChain{} = channel, offchain_state) do
    cond do
      channel.slash_sequence >= offchain_state.sequence ->
        {:error, "#{__MODULE__}: Offchain state is too old"}

      channel.initiator_amount + channel.responder_amount !=
          ChannelStateOffChain.total_amount(offchain_state) ->
        {:error, "#{__MODULE__}: Invalid total amount"}

      true ->
        ChannelStateOffChain.validate(offchain_state, pubkeys(channel))
    end
  end

  @doc """
  Executes slashing on a channel. Slashing should be validated beforehand with validate_slashing.
  """
  @spec apply_slashing(ChannelStateOnChain.t(), non_neg_integer(), ChannelStateOffChain.t()) ::
          ChannelStateOnChain.t()
  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, %ChannelStateOffChain{
        sequence: 0
      }) do
    %ChannelStateOnChain{
      channel
      | slash_close: block_height + channel.lock_period,
        slash_sequence: 0
    }
  end

  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, %ChannelStateOffChain{
        sequence: sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    %ChannelStateOnChain{
      channel
      | slash_close: block_height + channel.lock_period,
        slash_sequence: sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
    }
  end

  @spec encode_to_list(ChannelStateOnChain.t()) :: list()
  def encode_to_list(%ChannelStateOnChain{} = channel) do
    [
      :binary.encode_unsigned(@version),
      channel.initiator_pubkey,
      channel.responder_pubkey,
      :binary.encode_unsigned(channel.initiator_amount),
      :binary.encode_unsigned(channel.responder_amount),
      :binary.encode_unsigned(channel.lock_period),
      :binary.encode_unsigned(channel.slash_close),
      :binary.encode_unsigned(channel.slash_sequence)
    ]
  end

  @spec decode_from_list(integer(), list()) ::
          {:ok, ChannelStateOnChain.t()} | {:error, String.t()}
  def decode_from_list(@version, [
        initiator_pubkey,
        responder_pubkey,
        initiator_amount,
        responder_amount,
        lock_period,
        slash_close,
        slash_sequence
      ]) do
    {:ok,
     %ChannelStateOnChain{
       initiator_pubkey: initiator_pubkey,
       responder_pubkey: responder_pubkey,
       initiator_amount: :binary.decode_unsigned(initiator_amount),
       responder_amount: :binary.decode_unsigned(responder_amount),
       lock_period: :binary.decode_unsigned(lock_period),
       slash_close: :binary.decode_unsigned(slash_close),
       slash_sequence: :binary.decode_unsigned(slash_sequence)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
