defmodule Aecore.Peers.Sync do
  
  @peers_target_count Application.get_env(:aecore, :peers)[:peers_target_count]

  alias Aecore.Peers.Worker, as: Peers
  alias Aehttpclient.Client, as: HttpClient

  use GenServer

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def remove_dead do
    Peers.check_peers()
  end

  @spec refill :: :ok | {:error, term()}
  def refill do
    GenServer.call(__MODULE__, :refill)
  end

  @spec introduce_variety :: :ok
  def introduce_variety do
    GenServer.call(__MODULE__, :introduce_variety)
  end

  def handle_call(:introduce_variety, _from, state) do
    peers_count = map_size(Peers.all_peers())
    if peers_count >= @peers_target_count do
      random_peer = Enum.random(Map.keys(Peers.all_peers()))
      Logger.info(fn -> "Removing #{random_peer} to introduce variety" end)
      Peers.remove_peer(random_peer)
      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:refill, _from, state) do
    peers_count = map_size(Peers.all_peers())
    cond do
      peers_count == 0 ->
        Logger.error(fn -> "No peers" end)
        {:reply, {:error, "No peers"}, state}
      peers_count < @peers_target_count ->
        all_peers = Map.keys(Peers.all_peers())
        new_count = get_newpeers_and_add(all_peers)
        if new_count > 0 do
          Logger.info(fn -> "Aquired #{new_count} new peers" end)
          {:reply, :ok, state}
        else
          Logger.error(fn -> "No new peers added when trying to refill peers" end)
          {:reply, {:error, "No new peers added"}, state}
        end
      true ->  
        {:reply, :ok, state}
    end
  end

  defp get_newpeers_and_add(known) do
    known_count = length(known)
    known_set = MapSet.new(known)
    known
    |> Enum.shuffle
    |> Enum.take(@peers_target_count - known_count)
    |> Enum.reduce([], fn(peer, acc) ->
      case (HttpClient.get_peers(peer)) do
        {:ok, list} -> Enum.concat(list, acc)
        :error -> acc
      end
    end)
    |> Enum.reduce([], fn(peer, acc) ->
      if MapSet.member?(known_set, peer) do
        acc
      else
        [peer | acc]
      end
    end)
    |> Enum.shuffle
    |> Enum.take(Enum.min([@peers_target_count - known_count, known_count]))
    |> Enum.reduce(0, fn(peer, acc) -> 
      case Peers.add_peer(peer) do
        :ok -> acc+1
        _ -> acc
      end
    end)
  end
end
