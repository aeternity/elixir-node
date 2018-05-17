defmodule Aecore.Channel.Worker do
  @moduledoc """
  Module for managing Channels
  """

  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStatePeer
  alias Aecore.Channel.Tx.{ChannelCloseMutalTx, ChannelCloseSoloTx}
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool

  use GenServer

  require Logger

  @type role :: :initiator | :responder

  # State is map channel_id -> channel_info
  @type state :: %{binary() => ChannelStatePeer.t()}

  @type channels_onchain :: %{binary() => ChannelStateOnChain.t()}

  @type error :: {:error, binary()}

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}}
  end

  @doc """
  Imports channels from ChannelStatePeer object. Usefull for storage
  """
  @spec import_channel(ChannelStatePeer.t()) :: :ok | error()
  def import_channel(channel_state) do
    id = ChannelStatePeer.id(channel_state)
    GenServer.call(__MODULE__, {:import_channel, id, channel_state})
  end

  @doc """
  Import channel from open tx. Assumes no transactions were made
  """
  @spec import_from_open(SignedTx.t(), non_neg_integer(), role()) :: :ok | error()
  def import_from_open(open_tx, reserve, role) do
    peer_state = ChannelStatePeer.from_open(open_tx, reserve, role)
    import_channel(peer_state)
  end

  @doc """
  Imports channel from open tx and ChannelStateOffChain.
  """
  @spec import_from_open_and_state(SignedTx.t(), ChannelStateOffChain.t(), non_neg_integer(), role()) :: :ok | error()
  def import_from_open_and_state(open_tx, state, reserve, role) do
    peer_state = ChannelStatePeer.from_open_and_state(open_tx, state, reserve, role)
    import_channel(peer_state)
  end

  @doc """
  Initializes channel with temporary ID. This has to be called for every channel by both :initiator and :responder. 
  """
  @spec initialize(binary(), list(Wallet.pubkey()), list(non_neg_integer()), role(), non_neg_integer()) :: :ok | error()
  def initialize(temporary_id, pubkeys, amounts, role, channel_reserve) do
    GenServer.call(__MODULE__, {:initialize, temporary_id, pubkeys, amounts, role, channel_reserve})
  end

  @doc """
  Creates open transaction. Can only be called once per channel by :initiator. Returns pair: generated channelID, half signed SignedTx.
  """
  @spec create_open(binary(), non_neg_integer(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) :: {:ok, binary(), SignedTx.t()} | error()
  def create_open(temporary_id, locktime, fee, nonce, priv_key) do
    GenServer.call(__MODULE__, {:create_open, temporary_id, locktime, fee, nonce, priv_key})
  end

  @doc """
  Signs open transaction. Can only be called once per channel by :responder. Returns fully signed SignedTx and adds it to Pool.
  """
  @spec sign_open(binary(), SignedTx.t(), Wallet.privkey()) :: {:ok, binary(), SignedTx.t()} | error()
  def sign_open(temporary_id, open_tx, priv_key) do
    GenServer.call(__MODULE__, {:sign_open, temporary_id, open_tx, priv_key})
  end

  @doc """
  Notifies Channels Manager about confirmed channel open tx. Called by block validation stack.
  """
  @spec opened(SignedTx.t()) :: :ok
  def opened(open_tx) do
    case GenServer.call(__MODULE__, {:opened, open_tx}) do
      :ok ->
        :ok
      {:error, reason} = error->
        Logger.warn(reason)
        error
    end
  end

  @doc """
  Transfers amount to other peer in channel. Returns halfsigned channal offchain state. Can only be called on open channel.
  """
  @spec transfer(binary(), non_neg_integer(), Wallet.privkey()) :: {:ok, ChannelStateOffChain.t()} | error()
  def transfer(channel_id, amount, priv_key) do
    GenServer.call(__MODULE__, {:transfer, channel_id, amount, priv_key})
  end

  @doc """
  Handles received channel state. If it's half signed and validates: signs it and returns it.
  """
  @spec recv_state(ChannelStateOffChain.t(), Wallet.privkey()) :: {:ok, ChannelStateOffChain.t() | nil} | error()
  def recv_state(recv_state, priv_key) do
    GenServer.call(__MODULE__, {:recv_state, recv_state, priv_key})
  end

  @doc """
  Creates channel close transaction. This also blocks any new transactions from hapenning on channel.
  """
  @spec close(binary(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) :: {:ok, SignedTx.t()} | error()
  def close(channel_id, fee, nonce, priv_key) do
    GenServer.call(__MODULE__, {:close, channel_id, fee, nonce, priv_key})
  end

  @doc """
  Handles received half signed close tx. If it validates returns fully signed close tx and adds it to Pool.
  """
  @spec recv_close_tx(binary(), SignedTx.t(), Wallet.privkey()) :: {:ok, SignedTx.t()} | error()
  def recv_close_tx(channel_id, close_tx, priv_key) do
    GenServer.call(__MODULE__, {:recv_close_tx, channel_id, close_tx, priv_key})
  end

  @doc """
  Notifies Channel Manager about close tx being mined.
  """
  @spec closed(SignedTx.t()) :: :ok | error()
  def closed(close_tx) do
    GenServer.call(__MODULE__, {:closed, close_tx})
  end

  @doc """
  Slashes channel. Creates slash Tx and adds it to the pool.
  """
  @spec slash(binary(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) :: :ok | error()
  def slash(channel_id, fee, nonce, priv_key) do
    GenServer.call(__MODULE__, {:slash, channel_id, fee, nonce, priv_key})
  end

  @doc """
  Notifies channel manager about mined slash transaction. If channel Manager has newer state for coresponding channel it creates a slash transaction and add it to pool.
  """
  @spec slashed(SignedTx.t(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) :: :ok | error()
  def slashed(slash_tx, fee, nonce, priv_key) do
    GenServer.call(__MODULE__, {:slashed, slash_tx, fee, nonce, priv_key})
  end

  @doc """
  Returns map of all ChannelStatePeer objects.
  """
  @spec get_all_channels() :: %{binary() => ChannelStatePeer.t()}
  def get_all_channels() do
    GenServer.call(__MODULE__, :get_all_channels)
  end
  
  ## Server side
  #
  def handle_call({:import_channel, channel_id, channel_state}, _from, state) do
    {:reply, :ok, Map.put(state, channel_id, channel_state)}
  end

  def handle_call({:initialize, temporary_id, pubkeys, amounts, role, channel_reserve}, _from, state) do
    peer_state = ChannelStatePeer.initialize(temporary_id, pubkeys, amounts, channel_reserve, role)
    {:reply, :ok, Map.put(state, temporary_id, peer_state)}
  end

  def handle_call({:create_open, temporary_id, locktime, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, temporary_id)
    
    {:ok, new_peer_state, new_id, open_tx} = ChannelStatePeer.create_open(peer_state, locktime, fee, nonce, priv_key)

    new_state =
      state
      |>Map.drop([temporary_id])
      |>Map.put(new_id, new_peer_state)
    {:reply, {:ok, new_id, open_tx}, new_state}
  end

  def handle_call({:sign_open, temporary_id, open_tx, priv_key}, _from, state) do
    peer_state = Map.get(state, temporary_id)

    {:ok, new_peer_state, id, signed_open_tx} = ChannelStatePeer.sign_open(peer_state, open_tx, priv_key)
    Pool.add_transaction(signed_open_tx)

    new_state =
      state
      |>Map.drop([temporary_id])
      |>Map.put(id, new_peer_state)

    {:reply, {:ok, id, signed_open_tx}, new_state}
  end

  def handle_call({:opened, open_tx}, _from, state) do
    id = ChannelStateOnChain.id(SignedTx.data_tx(open_tx))
    
    if Map.has_key?(state, id) do
      peer_state = Map.get(state, id)
      new_peer_state = ChannelStatePeer.opened(peer_state)
      {:reply, :ok, Map.put(state, id, new_peer_state)}
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

  def handle_call({:slash, channel_id, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, channel_id)
    
    {:ok, new_peer_state, tx} = ChannelStatePeer.slash(peer_state, fee, nonce, priv_key)
    Pool.add_transaction(tx)
    {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
  end

  def handle_call({:slashed, slash_tx, fee, nonce, priv_key}, _from, state) do
    channel_id = 
      slash_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()
      |> ChannelCloseSoloTx.channel_id()

    if Map.has_key?(state, channel_id) do
      peer_state = Map.get(state, channel_id)
      {:ok, new_peer_state, tx} = ChannelStatePeer.slashed(peer_state, slash_tx, fee, nonce, priv_key)
      if tx != nil do
        Pool.add_transaction(tx)
      end
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    end
    {:reply, {:error, "Unknown channel"}, state}
  end

  def handle_call(:get_all_channels, _from, state) do
    {:reply, state, state}
  end

end
