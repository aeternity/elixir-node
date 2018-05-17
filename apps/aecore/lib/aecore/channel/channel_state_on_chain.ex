defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  State Channel OnChain structure
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash

  @type t :: %ChannelStateOnChain{
    initiator_pubkey: Wallet.pubkey(),
    responder_pubkey: Wallet.pubkey(),
    initiator_amount: integer(),
    responder_amount: integer(),
    lock_period: non_neg_integer(),
    closes_at: integer(),
    sequence: integer()
  }

  @type channels :: map() #TODO binary -> t()

  @doc """
  Definition of State Channel OnChain structure

  ## Parameters
  TODO
  """
  defstruct [
    :initiator_pubkey,
    :responder_pubkey,
    :initiator_amount,
    :responder_amount,
    :lock_period,
    :closes_at,
    :sequence,
    :slash_close,
    :slash_sequence,
    :slash_initiator,
    :slash_responder
  ]

  use ExConstructor

  @spec create(Wallet.pubkey(), Wallet.pubkey(), integer(), integer(), non_neg_integer()) :: ChannelStateOnChain.t()
  def create(initiator_pubkey, responder_pubkey, initiator_amount, responder_amount, lock_period) do
    %ChannelStateOnChain{
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      lock_period: lock_period,
      slash_close: -1,
      slash_sequence: -1
    }
  end

  def id(data_tx) do
    nonce = DataTx.nonce(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id(initiator_pubkey, responder_pubkey, nonce)
  end

  def id(initiator_pubkey, responder_pubkey, nonce) do
    bin = <<initiator_pubkey, nonce, responder_pubkey>>
    Hash.hash_blake2b(bin)
  end

  def amounts(%ChannelStateOnChain{initiator_amount: initiator_amount, responder_amount: responder_amount}) do [initiator_amount, responder_amount] end

  def pubkeys(%ChannelStateOnChain{initiator_pubkey: initiator_pubkey, responder_pubkey: responder_pubkey}) do [initiator_pubkey, responder_pubkey] end

  def active?(%ChannelStateOnChain{sequence: -1}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  def settled?(%ChannelStateOnChain{slash_close: slash_close} = channel, block_height) do
    block_height >= slash_close && (!active?(channel))
  end

  def validate_offchain(%ChannelStateOnChain{} = channel, offchain_state) do
    cond do
      channel.sequence >= ChannelStateOffChain.sequence(offchain_state) ->
        {:error, "Offchain state is too old"}

      true ->
        ChannelStateOffChain.validate(offchain_state, pubkeys(channel))
    end
  end

  def apply_offchain(%ChannelStateOnChain{} = channel, block_height, offchain_state) do
    %ChannelStateOnChain{
      channel | slash_close: block_height + channel.lock_period,
              slash_sequence: ChannelStateOffChain.sequence(offchain_state),
              slash_initiator: ChannelStateOffChain.initiator_amount(offchain_state),
              slash_responder: ChannelStateOffChain.responder_amount(offchain_state)}
  end

  def validate_withdraw(%ChannelStateOnChain{initiator_amount: initiator_amount}, :initiator, amount) do
    if amount <= initiator_amount do
      :ok
    else
      {:error, "Amount too big"}
    end
  end

  def validate_withdraw(%ChannelStateOnChain{responder_amount: responder_amount}, :responder, amount) do
    if amount <= responder_amount do
      :ok
    else
      {:error, "Amount too big"}
    end
  end

  def validate_withdraw(_, _, _) do
    {:error, "Wrong peer choice"}
  end

  def apply_withdraw(%ChannelStateOnChain{initiator_amount: initiator_amount} = channel, :initiator, amount) do
    %ChannelStateOnChain{channel | initiator_amount: initiator_amount - amount}
  end

  def apply_withdraw(%ChannelStateOnChain{responder_amount: responder_amount} = channel, :responder, amount) do
    %ChannelStateOnChain{channel | responder_amount: responder_amount - amount}
  end

  def validate_deposit(%ChannelStateOnChain{}, :initiator, amount) do
    if amount > 0 do
      :ok
    else
      {:error, "Amount negative"}
    end
  end

  def validate_deposit(%ChannelStateOnChain{}, :responder, amount) do
    if amount > 0 do
      :ok
    else
      {:error, "Amount negative"}
    end
  end

  def validate_deposit(_, _, _) do
    {:error, "Wrong peer choice"}
  end

  def apply_deposit(%ChannelStateOnChain{initiator_amount: initiator_amount} = channel, :initiator, amount) do
    %ChannelStateOnChain{channel | initiator_amount: initiator_amount + amount}
  end

  def apply_deposit(%ChannelStateOnChain{responder_amount: responder_amount} = channel, :responder, amount) do
    %ChannelStateOnChain{channel | responder_amount: responder_amount + amount}
  end

end
