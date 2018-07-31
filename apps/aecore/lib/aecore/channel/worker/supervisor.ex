defmodule Aecore.Channel.Worker.Supervisor do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Supervisor

  alias Aecore.Peers.P2PUtils
  alias Aecore.Channel.Session, as: ChannelSession

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      Aecore.Channel.Worker,
      Aecore.Channel.Worker.ChannelConnectionSupervisor,
      P2PUtils.ranch_child_spec(
        :channel_pool,
        num_of_acceptors(),
        channel_port(),
        ChannelSession,
        %{}
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def channel_port do
    Application.get_env(:aecore, :channels)[:channel_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :channels)[:ranch_acceptors]
  end
end
