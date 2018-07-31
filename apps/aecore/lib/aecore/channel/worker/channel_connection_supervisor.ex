defmodule Aecore.Channel.Worker.ChannelConnectionSupervisor do
  @moduledoc """
  Supervises the individual peer connection GenServer processes
  """

  use DynamicSupervisor

  alias Aecore.Channel.Session, as: ChannelSession

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_channel_connection(conn_info) do
    DynamicSupervisor.start_child(
      __MODULE__,
      Supervisor.child_spec(
        {ChannelSession, conn_info},
        restart: :temporary
      )
    )
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
