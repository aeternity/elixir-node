defmodule Aecore do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Application

  import Supervisor.Spec

  def start(_type, _args) do
    children = [
      Aecore.Persistence.Worker.Supervisor,
      Aecore.Chain.Worker.Supervisor,
      Aecore.Miner.Worker.Supervisor,
      Aecore.Tx.Pool.Worker.Supervisor,
      Aecore.Peers.Worker.Supervisor,
      Aecore.Channel.Worker.Supervisor,
      supervisor(Exexec, [], function: :start)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
