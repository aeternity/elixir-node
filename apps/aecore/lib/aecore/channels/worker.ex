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

  def handle_call({:new_channel, address}, _from, state) do
    {:reply, :ok, state}
  end
end
