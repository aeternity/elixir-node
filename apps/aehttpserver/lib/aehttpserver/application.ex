defmodule Aehttpserver.Application do
  use Application

  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(Aehttpserver.Web.Endpoint, []),
      # Start your own worker by calling: Aehttpserver.Worker.start_link(arg1, arg2, arg3)
      # worker(Aehttpserver.Worker, [arg1, arg2, arg3]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Aehttpserver.Supervisor]

    env_authorization = System.get_env("NODE_AUTHORIZATION")
    case env_authorization  do
      nil ->
        gen_authorization = UUID.uuid4
        Application.put_env(:aecore, :authorization, gen_authorization)
        Logger.info(fn -> "Authorization header for /node routes: #{gen_authorization}" end)
      env ->
        Application.put_env(:aecore, :authorization, env)
    end

    Supervisor.start_link(children, opts)
  end
end
