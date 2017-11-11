defmodule Aecore.Peers.Sync do

  @check_time 60_000
  @peers_target_count Application.get_env(:aecore, :peers)[:peers_target_count]

  alias Aecore.Peers.Worker, as: Peers
  alias Aehttpclient.Client, as: HttpClient

  use GenServer

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Process.send_after(self(), :work, 5_000)
    {:ok, state}
  end

  def handle_info(:work, state) do
    check_peers()
    introduce_variety()
    refill()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end

  defp check_peers do
    Peers.check_peers()
  end

  #To make sure no peer is more popular in network then others,
  #we remove one peer at random if we have at least target_count of peers.
  @spec introduce_variety :: :ok
  defp introduce_variety do
    peers_count = map_size(Peers.all_peers())
    if peers_count >= @peers_target_count do
      random_peer = Enum.random(Map.keys(Peers.all_peers()))
      Logger.info(fn -> "Removing #{random_peer} to introduce variety" end)
      Peers.remove_peer(random_peer)
      :ok
    else
      :ok
    end
  end

  #If our peer count is lower then @peers_target_count,
  #we request peers list from all known peers and choose at random
  #min(peers_we_need_to_have_target_count, peers_we_currently_have)
  #new peers to add.
  @spec refill :: :ok | {:error, term()}
  defp refill do
    peers_count = map_size(Peers.all_peers())
    cond do
      peers_count == 0 ->
        Logger.error(fn -> "No peers" end)
        {:error, "No peers"}
      peers_count < @peers_target_count ->
        all_peers = Map.keys(Peers.all_peers())
        new_count = get_newpeers_and_add(all_peers)
        if new_count > 0 do
          Logger.info(fn -> "Aquired #{new_count} new peers" end)
          :ok
        else
          Logger.error(fn -> "No new peers added when trying to refill peers" end)
          {:error, "No new peers added"}
        end
      true ->
        :ok
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

