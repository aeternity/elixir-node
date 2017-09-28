defmodule Aecore do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [supervisor(Aecore.Keys.Worker.Supervisor, [])]
	Supervisor.start_link(children, strategy: :one_for_one)
  end
end
