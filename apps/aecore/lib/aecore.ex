defmodule Aecore do
  @moduledoc """
  Main application supervisor
  """

  use Application

  def start(_type, _args) do
    children = [
      Aecore.Persistence.Worker.Supervisor,
      Aecore.Chain.Worker.Supervisor,
      Aecore.Miner.Worker.Supervisor,
      Aecore.Tx.Pool.Worker.Supervisor,
      Aecore.Peers.Worker.Supervisor,
      Aecore.Channel.Worker.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
