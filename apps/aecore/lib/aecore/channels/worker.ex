defmodule Aecore.Channel.Worker do
  @moduledoc """
  Module for managing Channels
  """

  use GenServer

  require Logger

  # State is map channel_id -> channel_info
  @type state :: map()

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(args) do
    {:ok, %{}}
  end

  ## Server side

  def handle_call({:import_channel, channel_id, channel_state}, _from, state) do
    {:reply, :ok, Map.put?(state, channel_id, channel_state)}
  end 

end
