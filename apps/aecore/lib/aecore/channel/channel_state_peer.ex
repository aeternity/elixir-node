defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Structure of Channel Peer State
  """


  alias Aecore.Channel.{ChannelStateOffChain, ChannelStateOnChain, ChannelStatePeer}
  alias Aecore.Channel.Worker, as: Channel
  alias Aecore.Channel.Tx.{ChannelCreateTx, ChannelCloseMutalTx, ChannelCloseSoloTx, ChannelSettleTx}
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

  require Logger

  use ExConstructor

  def role(%ChannelStatePeer{role: role}) do role end

  def state(%ChannelStatePeer{highest_signed_state: state}) do state end
  
  def fsm_state(%ChannelStatePeer{fsm_state: fsm_state}) do fsm_state end

  def id(peer_state) do
    peer_state
    |>state()
    |>ChannelStateOffChain.id()
  end

  def from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role) do
    %ChannelStatePeer{
      fsm_state: :open,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      highest_state: state,
      highest_signed_state: state,
      channel_reserve: channel_reserve
    }
  end

  def from_open(open_tx, channel_reserve, role) do
    data_tx = SignedTx.data_tx(open_tx)
    open_tx = DataTx.payload(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id = ChannelStateOnChain.id(data_tx)
    state = ChannelStateOffChain.create(
      id,
      0,
      ChannelCreateTx.initiator_amount(open_tx),
      ChannelCreateTx.responder_amount(open_tx)
    )
    from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role)
  end

  def from_open_and_state(open_tx, state, channel_reserve, role) do
    data_tx = SignedTx.data_tx(open_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role)
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

    new_peer_state = %ChannelStatePeer{peer_state |
      fsm_state: :half_signed,
      highest_state: zero_state,
      highest_signed_state: zero_state
    }

    with {:ok, half_signed_open_tx} <- SignedTx.sign_tx(open_tx_data, initiator_pubkey, priv_key) do
      {:ok, new_peer_state, id, half_signed_open_tx}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_open(%ChannelStatePeer{}) do
    {:error, "Invalid call"}
  end

  def sign_open(%ChannelStatePeer{fsm_state: :initialized, role: :responder, highest_state: our_state} = peer_state, half_signed_open_tx, priv_key) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey
    data_tx = SignedTx.data_tx(half_signed_open_tx)
    nonce = DataTx.nonce(data_tx)
    open_payload = DataTx.payload(data_tx)

    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
    initiator_amount = ChannelStateOffChain.initiator_amount(our_state)
    responder_amount = ChannelStateOffChain.responder_amount(our_state)

    cond do
      ChannelCreateTx.initiator_amount(open_payload) != initiator_amount ->
        {:error, "Wrong initiator amount"}
      
      ChannelCreateTx.responder_amount(open_payload) != responder_amount ->
        {:error, "Wrong responder amount"}

      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "Wrong peers"}

      true ->
        zero_state = ChannelStateOffChain.create(id, 0, initiator_amount, responder_amount)
        {:ok, fully_signed_open_tx} = SignedTx.sign_tx(half_signed_open_tx, responder_pubkey, priv_key)
        new_peer_state = %ChannelStatePeer{peer_state |
          fsm_state: :signed,
          highest_state: zero_state,
          highest_signed_state: zero_state
        }
        {:ok, new_peer_state, id, fully_signed_open_tx}
    end
  end

  def sign_open(%ChannelStatePeer{}) do
    {:error, "Invalid call"}
  end

  def opened(%ChannelStatePeer{fsm_state: :signed} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :open}
  end

  def opened(%ChannelStatePeer{fsm_state: :half_signed} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :open}
  end

  def opened(%ChannelStatePeer{} = state) do
    Logger.warn("Unexpected 'opened' call")
    state
  end

  def transfer(%ChannelStatePeer{fsm_state: :open, highest_state: highest_state, role: role} = peer_state, amount, priv_key) do
    {:ok, new_state} = ChannelStateOffChain.transfer(highest_state, role, amount)
    if ChannelStateOffChain.initiator_amount(new_state) < peer_state.channel_reserve
    || ChannelStateOffChain.responder_amount(new_state) < peer_state.channel_reserve
    do
      {:error, "Too big transfer"}
    else

      new_state_signed = ChannelStateOffChain.sign(new_state, role, priv_key) 

      new_peer_state = %ChannelStatePeer{peer_state |
        fsm_state: :update,
        highest_state: new_state_signed
      }

      {:ok, new_peer_state, new_state_signed}
    end
  end

  def transfer(%ChannelStatePeer{} = state) do
    {:error, "Can't transfer now; channel state is #{state.fsm_state}"}
  end

  def recv_state(%ChannelStatePeer{fsm_state: :open} = peer_state, new_state, priv_key) do
    with {:ok, new_peer_state, nil} <- recv_full_state(peer_state, new_state) do
      {:ok, new_peer_state, nil}
    else
      {:error, _reason} ->
        recv_half_state(peer_state, new_state, priv_key)
    end
  end

  def recv_state(%ChannelStatePeer{fsm_state: :update} = peer_state, new_state, _priv_key) do
    recv_full_state(peer_state, new_state)
  end

  def recv_state(%ChannelStatePeer{} = state) do
    {:error, "Can't receive state now; channel state is #{state.fsm_state}"}
  end

  defp recv_full_state(%ChannelStatePeer{highest_signed_state: highest_signed_state, highest_state: highest_state} = peer_state, new_state) do
    pubkeys = [peer_state.initiator_pubkey, peer_state.responder_pubkey]

    with :ok <- ChannelStateOffChain.validate_full_update(highest_signed_state, new_state, pubkeys) do
      if ChannelStateOffChain.sequence(highest_state) <= ChannelStateOffChain.sequence(new_state) do
        {:ok, %ChannelStatePeer{peer_state |
          fsm_state: :open,
          highest_signed_state: new_state,
          highest_state: new_state
        }, nil}
      else
        {:ok, %ChannelStatePeer{peer_state |
          highest_signed_state: new_state
        }, nil}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_half_state(%ChannelStatePeer{highest_signed_state: prev_state} = peer_state, new_state, priv_key) do
    pubkeys = [peer_state.initiator_pubkey, peer_state.responder_pubkey]

    with :ok <- ChannelStateOffChain.validate_half_update(prev_state, new_state, pubkeys, peer_state.role) do
      signed_new_state = ChannelStateOffChain.sign(new_state, peer_state.role, priv_key)
      new_peer_state = %ChannelStatePeer{peer_state |
        highest_signed_state: signed_new_state,
        highest_state: signed_new_state
      }
      
      with :ok <- ChannelStateOffChain.validate(signed_new_state, pubkeys) do
        {:ok, new_peer_state, signed_new_state}
      else
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
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
    {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, my_pubkey(peer_state), priv_key)
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
    
    {:ok, new_peer_state, close_signed_tx}
  end

  def close(%ChannelStatePeer{} = state) do
    {:error, "Can't close now; channel state is #{state.fsm_state}"}
  end

  def recv_close_tx(%ChannelStatePeer{fsm_state: :open, highest_signed_state: state} = peer_state, half_signed_tx, priv_key) do
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

  def recv_close_tx(%ChannelStatePeer{} = state) do
    {:error, "Can't receive close tx now; channel state is #{state.fsm_state}"}
  end

  def closed(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  def slash(%ChannelStatePeer{highest_signed_state: our_state} = peer_state, fee, nonce, priv_key) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
    
    data = DataTx.init(
      ChannelCloseSoloTx,
      %{state: our_state},
      my_pubkey(peer_state),
      fee,
      nonce)

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, my_pubkey(peer_state), priv_key)
    {:ok, new_peer_state, our_slash_tx}
  end

  def slashed(%ChannelStatePeer{highest_signed_state: our_state} = peer_state, slash_tx, fee, nonce, priv_key) do
    slash_sequence =
      slash_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()
      |> ChannelCloseSoloTx.sequence()

    if slash_sequence < ChannelStateOffChain.sequence(our_state) do
      slash(peer_state, fee, nonce, priv_key)
    else
      new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
      {:ok, new_peer_state, nil}
    end
  end

  def settle(%ChannelStatePeer{fsm_state: :closing} = peer_state, fee, nonce, priv_key) do
    data = DataTx.init(
      ChannelSettleTx,
      %{channel_id: id(peer_state)},
      ChannelStatePeer.my_pubkey(peer_state),
      fee,
      nonce
    )
    SignedTx.sign_tx(data, ChannelStatePeer.my_pubkey(peer_state), priv_key)
  end

  def settled(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | 
      fsm_state: :closed
    }
  end

  def my_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def my_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end

end
