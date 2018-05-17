defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Structure of Channel Peer State
  """


  alias Aecore.Channel.{ChannelStateOffChain, ChannelStateOnChain, ChannelStatePeer}
  alias Aecore.Channel.Worker, as: Channel
  alias Aecore.Channel.Tx.{ChannelCreateTx, ChannelCloseMutalTx}
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx

  @type states :: :initialized | :half_signed | :signed | :open | :update | :closing | :closed

  @type t :: %ChannelStatePeer{
    fsm_state: states(), 
    initiator_pubkey: Wallet.pubkey(),
    responder_pubkey: Wallet.pubkey(),
    role: Channel.roles(),
    highest_state: ChannelStateOffChain.t() | nil,
    highest_signed_state: ChannelStateOffChain.t() | nil,
    channel_reserve: non_neg_integer()
  }

  defstruct [
    :fsm_state,
    :initiator_pubkey,
    :responder_pubkey,
    :role,
    :highest_state,
    :highest_signed_state,
    :channel_reserve
  ]

  use ExConstructor

  def from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role) do
    %ChannelStatePeer{
      fsm_state: :opened,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      highest_state: state,
      highest_signed_state: state,
      channel_reserve: channel_reserve
    }
  end

  def initialize(temporary_id, 
                 [initiator_pubkey, responder_pubkey],
                 [initiator_amount, responder_amount],
                 channel_reserve, role) do
    initial_state = ChannelStateOffChain.create(temporary_id, 0, initiator_amount, responder_amount) 
    %ChannelStatePeer{
      fsm_state: :initialized,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      highest_state: initial_state,
      highest_signed_state: nil,
      channel_reserve: channel_reserve
    }
  end

  def create_open(%ChannelStatePeer{fsm_state: :initialized, role: :initiator, initiator_pubkey: initiator_pubkey, responder_pubkey: responder_pubkey} = peer_state, locktime, fee, nonce, priv_key) do
    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
    initiator_amount = ChannelStateOffChain.initiator_amount(peer_state.highest_state)
    responder_amount = ChannelStateOffChain.responder_amount(peer_state.highest_state)

    zero_state = ChannelStateOffChain.create(id, 0, initiator_amount, responder_amount)
    open_tx_data =
      DataTx.init(ChannelCreateTx,
                  %{initiator_amount: initiator_amount, responder_amount: responder_amount, locktime: locktime},
                  [initiator_pubkey, responder_pubkey],
                  fee,
                  nonce)
    {:ok, half_signed_open_tx} = SignedTx.sign_tx(open_tx_data, initiator_pubkey, priv_key)
    new_peer_state = %ChannelStatePeer{peer_state |
      fsm_state: :helf_signed,
      highest_state: zero_state,
      highest_signed_state: zero_state #TODO Zero state should be considered signed
    }

    {:ok, new_peer_state, id, half_signed_open_tx}
  end

  def sign_open(%ChannelStatePeer{fsm_state: :initialized, role: :responder} = peer_state, half_signed_open_tx, priv_key) do
    #TODO validation
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey
    nonce =
      half_signed_open_tx
      |> SignedTx.data_tx()
      |> DataTx.nonce()
    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
    initiator_amount = ChannelStateOffChain.initiator_amount(peer_state.highest_state)
    responder_amount = ChannelStateOffChain.responder_amount(peer_state.highest_state)

    zero_state = ChannelStateOffChain.create(id, 0, initiator_amount, responder_amount)
    {:ok, fully_signed_open_tx} = SignedTx.sign_tx(half_signed_open_tx, responder_pubkey, priv_key)
    new_peer_state = %ChannelStatePeer{peer_state |
      fsm_state: :signed,
      highest_state: zero_state,
      highest_signed_state: zero_state
    }

    {:ok, new_peer_state, id, fully_signed_open_tx}
  end

  def opened(%ChannelStatePeer{fsm_state: :signed} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :opened}
  end

  def transfer(%ChannelStatePeer{fsm_state: :opened, highest_state: highest_state, role: role} = peer_state, amount, priv_key) do
    {:ok, new_state} = ChannelStateOffChain.transfer(highest_state, role, amount)
    new_state_signed = ChannelStateOffChain.sign(new_state, role, priv_key) 

    new_peer_state = %ChannelStatePeer{peer_state |
      fsm_state: :update,
      highest_state: new_state_signed
    }

    {:ok, new_peer_state, new_state_signed}
  end

  def recv_state(%ChannelStatePeer{fsm_state: :opened, highest_signed_state: prev_state} = peer_state, new_state, priv_key) do
    pubkeys = [peer_state.initiator_pubkey, peer_state.responder_pubkey]
    with :ok <- ChannelStateOffChain.validate_update(prev_state, new_state, pubkeys, peer_state.role) do
      signed_new_state = ChannelStateOffChain.sign(new_state, peer_state.role, priv_key)
      new_peer_state = %ChannelStatePeer{peer_state |
        highest_signed_state: signed_new_state,
        highest_state: signed_new_state
      }

      {:ok, new_peer_state, signed_new_state}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def recv_state(%ChannelStatePeer{fsm_state: :update, highest_state: prev_state} = peer_state, new_state, _priv_key) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey

    cond do
      !ChannelStateOffChain.equal?(prev_state, new_state) ->
        {:error, "received state is different then it should be"}
      
      !ChannelStateOffChain.validate(new_state, [initiator_pubkey, responder_pubkey])->
        {:error, "received state is invalid"}

      true ->
        {:ok, %ChannelStatePeer{peer_state |
          fsm_state: :opened,
          highest_signed_state: new_state,
          highest_state: new_state
        }, nil}
    end
  end

  def close(%ChannelStatePeer{fsm_state: :open, highest_signed_state: state} = peer_state, fee, nonce, priv_key) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey

    close_tx =
      DataTx.init(
        ChannelCloseMutalTx,
        %{
          channel_id: ChannelStateOffChain.id(state),
          initiator_amount: ChannelStateOffChain.initiator_amount(state),
          responder_amount: ChannelStateOffChain.responder_amount(state)
        },
        [initiator_pubkey, responder_pubkey],
        fee,
        nonce
      )
    {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, my_pubkey(state), priv_key)
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
    
    {:ok, new_peer_state, close_signed_tx}
  end

  def recv_close_tx(%ChannelStatePeer{fsm_state: :opened, highest_signed_state: state} = peer_state, half_signed_tx, priv_key) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey
    data_tx = SignedTx.data_tx(half_signed_tx)
    close_tx = DataTx.payload(data_tx)

    cond do
      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "Invalid senders"}
      
      ChannelCloseMutalTx.channel_id(close_tx) != ChannelStateOffChain.id(state) ->
        {:error, "Invalid id"}

      ChannelCloseMutalTx.initiator_amount(close_tx) != ChannelStateOffChain.initiator_amount(state) ->
        {:error, "Invalid initiator_amount"}
    
      ChannelCloseMutalTx.responder_amount(close_tx) != ChannelStateOffChain.responder_amount(state) ->
        {:error, "Invalid responder_amount"}

      true ->
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
        {:ok, signed_close_tx} = SignedTx.sign_tx(half_signed_tx, my_pubkey(peer_state), priv_key)
        {:ok, new_peer_state, signed_close_tx}
    end
  end

  def closed(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  def my_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def my_pubkey(%ChannelStatePeer{role: :repsonder, responder_pubkey: pubkey}) do
    pubkey
  end

end
