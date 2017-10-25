defmodule Aecore.Peers.Worker do
  @moduledoc """
  Peer manager module
  """

  use GenServer

  alias Aehttpclient.Client
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Serialization

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(initial_peers) do
    {:ok, initial_peers}
  end

  @spec add_peer(term) :: :ok | {:error, term()} | :error
  def add_peer(uri) do
    GenServer.call(__MODULE__, {:add_peer, uri})
  end

  @spec remove_peer(term) :: :ok | :error
  def remove_peer(uri) do
    GenServer.call(__MODULE__, {:remove_peer, uri})
  end

  @spec check_peers() :: :ok
  def check_peers() do
    GenServer.call(__MODULE__, :check_peers)
  end

  @spec all_peers() :: list()
  def all_peers() do
    GenServer.call(__MODULE__, :all_peers)
  end

  @spec broadcast_tx(tx :: map()) :: term()
  def broadcast_tx(tx) do
    GenServer.cast(__MODULE__, {:broadcast_tx, tx})
  end

  @spec genesis_block_header_hash() :: term()
  def genesis_block_header_hash() do
    Block.genesis_header()
    |> BlockValidation.block_header_hash()
    |> Base.encode16()
  end

  def handle_call({:add_peer,uri}, _from, peers) do
    if(!Enum.member?(peers,uri)) do
      case(Client.get_info(uri)) do
        {:ok, info} ->
          if(Map.get(info,:genesis_block_hash) == genesis_block_header_hash()) do
            {:reply, :ok, [uri | peers]}
          else
            {:reply, {:error, "Genesis header hash not valid"}, peers}
          end
        :error ->
          {:reply, :error, peers}
      end
    else
      {:reply, {:error, "Peer already in list"}, peers}
    end
  end

  def handle_call({:remove_peer, uri}, _from, peers) do
    if(Enum.member?(peers,uri)) do
      {:reply, :ok, List.delete(peers, uri)}
    else
      {:reply, {:error, "Peer not found"}, peers}
    end
  end

  def handle_call(:check_peers, _from, peers) do
    updated_peers = Enum.filter(peers, fn(peer) ->
      {status, info} = Client.get_info(peer)
      :ok == status &&
        Map.get(info, :genesis_block_hash) == genesis_block_header_hash()
      end)
    {:reply, :ok, updated_peers}
  end

  def handle_call(:all_peers, _from, peers) do
    {:reply, peers, peers}
  end

  def handle_cast({:broadcast_tx, tx}, peers) do
    serialized_tx = Serialization.txs(tx, :serialize)
    for peer <- peers do
      Client.broadcast_tx(peer, serialized_tx)
    end

    {:noreply, peers}
  end
  def handle_cast(_any, peers) do
    {:noreply, peers}
  end
end
