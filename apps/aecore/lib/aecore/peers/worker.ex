defmodule Aecore.Peers.Worker do
  @moduledoc """
  Peer manager module
  """

  use GenServer

  alias Aecore.Peers.Sync
  alias Aehttpclient.Client
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.Block
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Header

  require Logger

  @mersenne_prime 2_147_483_647
  @peers_max_count Application.get_env(:aecore, :peers)[:peers_max_count]
  @probability_of_peer_remove_when_max 0.5

  @type peers :: %{non_neg_integer() => %{latest_block: String.t(), uri: String.t()}}

  def start_link(_args) do
    GenServer.start_link(
      __MODULE__,
      %{peers: %{}, nonce: get_peer_nonce()},
      name: __MODULE__
    )
  end

  ## Client side

  @spec chain_synced?() :: boolean()
  def chain_synced? do
    GenServer.call(__MODULE__, :is_chain_synced)
  end

  @spec add_peer(String.t()) :: :ok | {:error, term} | :error
  def add_peer(uri) do
    GenServer.call(__MODULE__, {:add_peer, uri})
  end

  @spec remove_peer(String.t()) :: :ok | :error
  def remove_peer(uri) do
    GenServer.call(__MODULE__, {:remove_peer, uri})
  end

  @spec check_peers() :: :ok
  def check_peers do
    GenServer.call(__MODULE__, :check_peers)
  end

  @spec all_uris() :: list(binary())
  def all_uris do
    all_peers()
    |> Map.values()
    |> Enum.map(fn %{uri: uri} -> uri end)
  end

  @spec all_peers() :: peers
  def all_peers do
    GenServer.call(__MODULE__, :all_peers)
  end

  @spec genesis_block_header_hash() :: term()
  def genesis_block_header_hash do
    BlockValidation.block_header_hash(Block.genesis_block().header)
  end

  @spec schedule_add_peer(String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def schedule_add_peer(uri, nonce) do
    GenServer.cast(__MODULE__, {:schedule_add_peer, uri, nonce})
  end

  @doc """
  Gets a random peer nonce
  """
  @spec get_peer_nonce() :: non_neg_integer()
  def get_peer_nonce() do
    case :ets.info(:nonce_table) do
      :undefined -> create_nonce_table()
      _ -> :table_created
    end

    case :ets.lookup(:nonce_table, :nonce) do
      [] ->
        nonce = :rand.uniform(@mersenne_prime)
        :ets.insert(:nonce_table, {:nonce, nonce})
        nonce

      _ ->
        :ets.lookup(:nonce_table, :nonce)[:nonce]
    end
  end

  @spec broadcast_block(Block.t()) :: :ok
  def broadcast_block(block) do
    spawn(fn ->
      Client.send_block(block, all_uris())
      :ok
    end)

    :ok
  end

  @spec broadcast_tx(SignedTx.t()) :: :ok
  def broadcast_tx(tx) do
    spawn(fn ->
      Client.send_tx(tx, all_uris())
    end)

    :ok
  end

  ## Server side

  def init(initial_peers) do
    {:ok, initial_peers}
  end

  def handle_call(:is_chain_synced, _from, %{peers: peers} = state) do
    local_latest_block_height = Chain.top_height()

    peer_uris =
      peers
      |> Map.values()
      |> Enum.map(fn %{uri: uri} -> uri end)

    peer_latest_block_heights =
      Enum.map(peer_uris, fn uri ->
        case Client.get_info(uri) do
          {:ok, info} ->
            info.current_block_height

          :error ->
            0
        end
      end)

    is_synced =
      if Enum.empty?(peer_uris) do
        true
      else
        Enum.max(peer_latest_block_heights) <= local_latest_block_height
      end

    {:reply, is_synced, state}
  end

  def handle_call({:add_peer, uri}, _from, state) do
    add_peer(uri, state)
  end

  def handle_call({:remove_peer, uri}, _from, %{peers: peers} = state) do
    if Map.has_key?(peers, uri) do
      Logger.info(fn -> "Removed #{uri} from the peer list" end)
      {:reply, :ok, %{state | peers: Map.delete(peers, uri)}}
    else
      Logger.error(fn -> "#{uri} is not in the peer list" end)
      {:reply, {:error, "Peer not found"}, %{state | peers: peers}}
    end
  end

  @doc """
  Filters the peers map by checking if the response status from a GET /info
  request is :ok and if the genesis block hash is the same as the one
  in the current node. After that the current block hash for every peer
  is updated if the one in the latest GET /info request is different.
  """
  def handle_call(:check_peers, _from, %{peers: peers} = state) do
    filtered_peers =
      :maps.filter(
        fn _, %{uri: uri} ->
          case Client.get_info(uri) do
            {:ok, info} ->
              binary_genesis_hash = Header.base58c_decode(info.genesis_block_hash)
              binary_genesis_hash == genesis_block_header_hash()

            _ ->
              false
          end
        end,
        peers
      )

    updated_peers =
      for {nonce, %{uri: uri, latest_block: latest_block}} <- filtered_peers, into: %{} do
        {_, info} = Client.get_info(uri)

        if info.current_block_hash != latest_block do
          {nonce, %{uri: uri, latest_block: info.current_block_hash}}
        else
          {nonce, %{uri: uri, latest_block: latest_block}}
        end
      end

    removed_peers_count = Enum.count(peers) - Enum.count(filtered_peers)

    if removed_peers_count > 0 do
      Logger.info(fn ->
        "#{removed_peers_count} peers were removed after the check"
      end)
    end

    {:reply, :ok, %{state | peers: updated_peers}}
  end

  def handle_call(:all_peers, _from, %{peers: peers} = state) do
    {:reply, peers, state}
  end

  ## Async operations
  def handle_cast({:schedule_add_peer, uri, nonce}, %{peers: peers} = state) do
    if Map.has_key?(peers, nonce) do
      {:noreply, state}
    else
      {:reply, _, newstate} = add_peer(uri, state)
      {:noreply, newstate}
    end
  end

  def handle_cast(any, state) do
    Logger.info("[Peers] Unhandled cast message:  #{inspect(any)}")
    {:noreply, state}
  end

  ## Internal functions
  defp add_peer(uri, state) do
    %{peers: peers} = state

    state_has_uri =
      peers
      |> Map.values()
      |> Enum.map(fn %{uri: uri} -> uri end)
      |> Enum.member?(uri)

    if state_has_uri do
      Logger.debug(fn ->
        "Skipped adding #{uri}, already known"
      end)

      {:reply, {:error, "Peer already known"}, state}
    else
      case check_peer(uri, get_peer_nonce()) do
        {:ok, info} ->
          cond do
            Map.has_key?(peers, info.peer_nonce) ->
              Logger.debug(fn ->
                "Skipped adding #{uri}, same nonce already present"
              end)

              {:reply, {:error, "Peer already known"}, state}

            should_a_peer_be_added?(map_size(peers)) ->
              peers_update1 = trim_peers(peers)

              updated_peers =
                Map.put(peers_update1, info.peer_nonce, %{
                  uri: uri,
                  latest_block: info.current_block_hash
                })

              Logger.info(fn -> "Added #{uri} to the peer list" end)
              Sync.ask_peers_for_unknown_blocks(updated_peers)
              Sync.add_unknown_peer_pool_txs(updated_peers)
              {:reply, :ok, %{state | peers: updated_peers}}

            true ->
              Logger.debug(fn -> "Max peers reached. #{uri} not added" end)
              {:reply, :ok, state}
          end

        {:error, "Equal peer nonces"} ->
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.error(fn -> "Failed to add peer. reason=#{reason}" end)
          {:reply, {:error, reason}, state}
      end
    end
  end

  defp trim_peers(peers) do
    if map_size(peers) >= @peers_max_count do
      random_peer = Enum.random(Map.keys(peers))
      Logger.debug(fn -> "Max peers reached. #{random_peer} removed" end)
      Map.delete(peers, random_peer)
    else
      peers
    end
  end

  defp create_nonce_table do
    :ets.new(:nonce_table, [:named_table])
  end

  defp check_peer(uri, own_nonce) do
    case Client.get_info(uri) do
      {:ok, info} ->
        binary_genesis_hash = Header.base58c_decode(info.genesis_block_hash)

        cond do
          own_nonce == info.peer_nonce ->
            {:error, "Equal peer nonces"}

          binary_genesis_hash != genesis_block_header_hash() ->
            {:error, "Genesis header hash not valid"}

          !Map.has_key?(info, :server) || info.server != "aehttpserver" ->
            {:error, "Peer is not an aehttpserver"}

          true ->
            {:ok, info}
        end

      _error ->
        {:error, "Request error"}
    end
  end

  defp should_a_peer_be_added?(peers_count) do
    peers_count < @peers_max_count || :rand.uniform() < @probability_of_peer_remove_when_max
  end
end
