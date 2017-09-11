defmodule Aecore do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(Aecore.Peers.Worker.Supervisor, []),
      # Start your own worker by calling: Aecore.Worker.start_link(arg1, arg2, arg3)
      # worker(BynkAdmin.Worker, [arg1, arg2, arg3]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
