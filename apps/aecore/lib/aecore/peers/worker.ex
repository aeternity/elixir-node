defmodule Aecore.Peers.Worker do
  @moduledoc """
  Contains peer handling functionality.
  """

  use GenServer

  alias Aecore.Peers.Worker.PeerConnectionSupervisor
  alias Aecore.Peers.PeerConnection
  alias Aecore.Chain.Block
  alias Aecore.Keys
  alias Aehttpclient.Client

  require Logger

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_args) do
    peers = %{}

    {pubkey, privkey} = Keys.keypair(:peer)

    local_peer = %{privkey: privkey, pubkey: pubkey}
    state = %{peers: peers, local_peer: local_peer}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  @spec state() :: map()
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @spec all_peers() :: list()
  def all_peers do
    GenServer.call(__MODULE__, :all_peers)
  end

  @spec all_pids() :: list()
  def all_pids do
    GenServer.call(__MODULE__, :all_pids)
  end

  def add_peer(conn_info) do
    GenServer.call(__MODULE__, {:add_peer, conn_info})
  end

  @spec remove_peer(Keys.pubkey()) :: :ok
  def remove_peer(pubkey) do
    GenServer.call(__MODULE__, {:remove_peer, pubkey})
  end

  def get_random(count) do
    GenServer.call(__MODULE__, {:get_random, count})
  end

  def get_random(count, exclude) do
    GenServer.call(__MODULE__, {:get_random, count, exclude})
  end

  def have_peer?(peer_pubkey) do
    GenServer.call(__MODULE__, {:have_peer?, peer_pubkey})
  end

  def broadcast_block(%Block{} = block) do
    GenServer.cast(__MODULE__, {:broadcast_block, block})
  end

  def get_info_try_connect(uri) do
    case Client.get_peer_info(uri) do
      {:ok, peer_info} ->
        try_connect(peer_info)

      {:error, _reason} = error ->
        error
    end
  end

  @spec try_connect(map()) :: :ok
  def try_connect(peer_info) do
    GenServer.cast(__MODULE__, {:try_connect, peer_info})
  end

  def rlp_encode_peers(peers) do
    Enum.map(peers, fn %{host: host, port: port, pubkey: pubkey} ->
      list = [to_string(host), :binary.encode_unsigned(port), pubkey]
      ExRLP.encode(list)
    end)
  end

  def rlp_decode_peers(encoded_peers) do
    Enum.map(encoded_peers, fn encoded_peer ->
      [host, port_bin, pubkey] = ExRLP.decode(encoded_peer)

      %{
        host: to_charlist(host),
        port: :binary.decode_unsigned(port_bin),
        pubkey: pubkey
      }
    end)
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:all_peers, _from, %{peers: peers} = state) do
    all_peers = peers |> Map.values() |> prepare_peers()
    {:reply, all_peers, state}
  end

  def handle_call(:all_pids, _from, %{peers: peers} = state) do
    pids = for peer <- Map.values(peers), do: peer.connection
    {:reply, pids, state}
  end

  def handle_call(
        {:add_peer, %{pubkey: pubkey} = peer_info},
        _from,
        %{peers: peers} = state
      ) do
    updated_peers = Map.put(peers, pubkey, peer_info)
    updated_state = %{state | peers: updated_peers}
    {:reply, :ok, updated_state}
  end

  def handle_call({:remove_peer, pubkey}, _from, %{peers: peers} = state) do
    updated_peers = Map.delete(peers, pubkey)
    updated_state = %{state | peers: updated_peers}
    {:reply, :ok, updated_state}
  end

  def handle_call({:get_random, count}, _from, %{peers: peers} = state) do
    random_peers =
      peers
      |> Map.values()
      |> Enum.take_random(count)
      |> prepare_peers()

    {:reply, random_peers, state}
  end

  def handle_call({:get_random, count, exclude}, _from, %{peers: peers} = state) do
    filtered_peers =
      peers
      |> Map.values()
      |> Enum.filter(fn peer ->
        !Enum.any?(exclude, fn to_be_excluded -> peer.pubkey == to_be_excluded end)
      end)

    random_peers = filtered_peers |> Enum.take_random(count) |> prepare_peers()
    {:reply, random_peers, state}
  end

  def handle_call({:have_peer?, peer_pubkey}, _from, %{peers: peers} = state) do
    have_peer = Map.has_key?(peers, peer_pubkey)
    {:reply, have_peer, state}
  end

  def handle_cast(
        {:try_connect, peer_info},
        %{peers: peers, local_peer: %{privkey: privkey, pubkey: pubkey}} = state
      ) do
    if peer_info.pubkey != pubkey do
      case Map.has_key?(peers, peer_info.pubkey) do
        false ->
          conn_info =
            Map.merge(peer_info, %{r_pubkey: peer_info.pubkey, privkey: privkey, pubkey: pubkey})

          {:ok, _pid} = PeerConnectionSupervisor.start_peer_connection(conn_info)
          {:noreply, state}

        true ->
          Logger.error(fn -> "Won't add #{inspect(peer_info)}, already in peer list" end)
          {:noreply, state}
      end
    else
      Logger.info(fn -> "Can't add ourself" end)
      {:noreply, state}
    end
  end

  def handle_cast({:broadcast_block, block}, %{peers: peers} = state) do
    Enum.each(peers, fn {_pubkey, peer} ->
      PeerConnection.send_new_block(block, peer.connection)
    end)

    {:noreply, state}
  end

  defp prepare_peers(peers) do
    Enum.map(peers, fn peer -> Map.delete(peer, :connection) end)
  end
end
