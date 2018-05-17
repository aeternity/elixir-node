defmodule Aecore.Channel.Worker do
  @moduledoc """
  Module for managing Channels
  """

  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStatePeer
  alias Aecore.Channel.Tx.ChannelCloseMutalTx
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool

  use GenServer

  require Logger

  @type roles :: :initiator | :responder

  # State is map channel_id -> channel_info
  @type state :: map()

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(args) do
    {:ok, %{}}
  end

  def import_channel(channel_id, channel_state) do
    GenServer.call(__MODULE__, {:import_channel, channel_id, channel_state})
  end

  def initialize(temporary_id, pubkeys, amounts, role, channel_reserve) do
    GenServer.call(__MODULE__, {:initialize, temporary_id, pubkeys, amounts, role, channel_reserve})
  end

  def create_open(temporary_id, locktime, fee, nonce, priv_key) do
    GenServer.call(__MODULE__, {:create_open, temporary_id, locktime, fee, nonce, priv_key})
  end

  def opened(open_tx) do
    GenServer.call(__MODULE__, {:opened, open_tx})
  end

  def transfer(channel_id, amount, priv_key) do
    GenServer.call(__MODULE__, {:transfer, channel_id, amount, priv_key})
  end

  def recv_state(recv_state, priv_key) do
    GenServer.call(__MODULE__, {:recv_state, recv_state, priv_key})
  end

  def close(channel_id, priv_key) do
    GenServer.call(__MODULE__, {:close, channel_id, priv_key})
  end

  def recv_close_tx(channel_id, close_tx) do
    GenServer.call(__MODULE__, {:recv_close_id, channel_id, close_tx})
  end

  def closed(close_tx) do
    GenServer.call(__MODULE__, {:closed, close_tx})
  end

  ## Server side

  def handle_call({:import_channel, channel_id, channel_state}, _from, state) do
    {:reply, :ok, Map.put(state, channel_id, channel_state)}
  end

  def handle_call({:initialize, temporary_id, pubkeys, amounts, role, channel_reserve}, _from, state) do
    peer_state = ChannelStatePeer.initialize(temporary_id, pubkeys, amounts, channel_reserve, role)
    {:reply, temporary_id, Map.put(state, temporary_id, peer_state)}
  end

  def handle_call({:create_open, temporary_id, locktime, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, temporary_id)
    
    {:ok, new_peer_state, new_id, open_tx} = ChannelStatePeer.create_open(peer_state, locktime, fee, nonce, priv_key)

    new_state =
      state
      |>Map.pop(temporary_id)
      |>Map.put(new_id, new_peer_state)
    {:reply, {new_id, open_tx}, new_state}
  end

  def handle_call({:opened, open_tx}, _from, state) do
    id = ChannelStateOnChain.id(SignedTx.data_tx(open_tx))
    
    if Map.has_key?(state, id) do
      peer_state = Map.get(state, id)
      new_peer_state = ChannelStatePeer.opened(peer_state)
      {:reply, :ok, Map.put(state, id, peer_state)}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:transfer, id, amount, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    {:ok, new_peer_state, offchain_state} = ChannelStatePeer.transfer(peer_state, amount, priv_key)

    {:reply, {:ok, offchain_state}, Map.put(state, id, new_peer_state)}
  end

  def handle_call({:recv_state, recv_state, priv_key}, _from, state) do
    id = ChannelStateOffChain.id(recv_state)
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, offchain_state} <- ChannelStatePeer.recv_state(peer_state, recv_state, priv_key) do
      {:reply, {:ok, offchain_state}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:close, id, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, close_tx} <- ChannelStatePeer.close(peer_state, fee, nonce, priv_key) do
      {:reply, {:ok, close_tx}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:recv_close_tx, id, close_tx, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, signed_close_tx} <- ChannelStatePeer.recv_close_tx(peer_state, close_tx, priv_key),
         :ok <- Pool.add_transaction(signed_close_tx) do
      {:reply, {:ok, signed_close_tx}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
      :error ->
        {:reply, {:error, "Transacion Pool error (Invalid recvieved tx signature?)"}, state}
    end
  end

  def handle_call({:closed, close_tx}, _from, state) do 
    id = 
      close_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()
      |> ChannelCloseMutalTx.channel_id()

    if Map.has_key?(state, id) do
      peer_state = Map.get(state, id)
      new_peer_state = ChannelStatePeer.closed(peer_state)
      {:reply, :ok, Map.put(state, id, new_peer_state)}
    else
      {:reply, :ok, state}
    end
  end
end
