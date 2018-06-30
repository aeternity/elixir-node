defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  State Channel OnChain structure
  """

  require Logger

  alias Aecore.Keys.Wallet
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash
  alias Aeutil.Serialization

  @type t :: %ChannelStateOnChain{
          initiator_pubkey: Wallet.pubkey(),
          responder_pubkey: Wallet.pubkey(),
          initiator_amount: integer(),
          responder_amount: integer(),
          lock_period: non_neg_integer(),
          slash_close: integer(),
          slash_sequence: integer()
        }

  @type id :: binary()

  @doc """
  Definition of State Channel OnChain structure

  ## Parameters
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

  @spec create(Wallet.pubkey(), Wallet.pubkey(), integer(), integer(), non_neg_integer()) ::
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
  Generates channel id from ChannelCreateTx.
  """
  @spec id(DataTx.t()) :: id()
  def id(data_tx) do
    nonce = DataTx.nonce(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id(initiator_pubkey, responder_pubkey, nonce)
  end

  @doc """
  Generates channel id from detail of ChannelCreateTx.
  """
  @spec id(Wallet.pubkey(), Wallet.pubkey(), non_neg_integer()) :: id()
  def id(initiator_pubkey, responder_pubkey, nonce) do
    binary_data = initiator_pubkey <> <<nonce::size(64)>> <> responder_pubkey

    Hash.hash_blake2b(binary_data)
  end

  @spec amounts(ChannelStateOnChain.t()) :: list(non_neg_integer())
  def amounts(%ChannelStateOnChain{
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    [initiator_amount, responder_amount]
  end

  @spec initiator_pubkey(ChannelStateOnChain.t()) :: Wallet.pubkey()
  def initiator_pubkey(%ChannelStateOnChain{initiator_pubkey: initiator_pubkey}) do
    initiator_pubkey
  end

  @spec responder_pubkey(ChannelStateOnChain.t()) :: Wallet.pubkey()
  def responder_pubkey(%ChannelStateOnChain{responder_pubkey: responder_pubkey}) do
    responder_pubkey
  end

  @spec pubkeys(ChannelStateOnChain.t()) :: list(Wallet.pubkey())
  def pubkeys(%ChannelStateOnChain{
        initiator_pubkey: initiator_pubkey,
        responder_pubkey: responder_pubkey
      }) do
    [initiator_pubkey, responder_pubkey]
  end

  @doc """
  Returns true if channel wasn't slashed. (Closed channels should be removed from Channels state tree)
  """
  @spec active?(ChannelStateOnChain.t()) :: boolean()
  def active?(%ChannelStateOnChain{slash_close: 0}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  @doc """
  Returns true if Channel can be settled. (If Channel was slashed and current block height exceeds locktime)
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

      channel.initiator_amount != ChannelStateOffChain.initiator_amount(offchain_state) ->
        {:error, "#{__MODULE__}: Wrong initator amount"}

      channel.responder_amount != ChannelStateOffChain.responder_amount(offchain_state) ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      true ->
        :ok
    end
  end

  def validate_slashing(%ChannelStateOnChain{} = channel, offchain_state) do
    cond do
      channel.slash_sequence >= ChannelStateOffChain.sequence(offchain_state) ->
        {:error, "#{__MODULE__}: Offchain state is too old"}

      channel.initiator_amount + channel.responder_amount !=
          ChannelStateOffChain.total_amount(offchain_state) ->
        {:error, "#{__MODULE__}: Invalid total amount"}

      true ->
        ChannelStateOffChain.validate(offchain_state, pubkeys(channel))
    end
  end

  @doc """
  Executes slashing on channel. Slashing should be validated before with validate_slashing.
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

  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, offchain_state) do
    %ChannelStateOnChain{
      channel
      | slash_close: block_height + channel.lock_period,
        slash_sequence: ChannelStateOffChain.sequence(offchain_state),
        initiator_amount: ChannelStateOffChain.initiator_amount(offchain_state),
        responder_amount: ChannelStateOffChain.responder_amount(offchain_state)
    }
  end

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), t()) :: binary() | {:error, String.t()}
  def rlp_encode(tag, version, %ChannelStateOnChain{} = channel) do
    list = [
      tag,
      version,
      channel.initiator_pubkey,
      channel.responder_pubkey,
      channel.initiator_amount,
      channel.responder_amount,
      channel.lock_period,
      channel.slash_close,
      channel.slash_sequence
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  @spec rlp_decode(list()) :: {:ok, ChannelStateOnChain.t()} | {:error, String.t()}
  def rlp_decode([
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
       initiator_amount: Serialization.transform_item(initiator_amount, :int),
       responder_amount: Serialization.transform_item(responder_amount, :int),
       lock_period: Serialization.transform_item(lock_period, :int),
       slash_close: Serialization.transform_item(slash_close, :int),
       slash_sequence: Serialization.transform_item(slash_sequence, :int)
     }}
  end

  def rlp_decode(_, _) do
    {:error, "#{__MODULE__}: Invalid ChannelStateOnChain structure"}
  end
end
