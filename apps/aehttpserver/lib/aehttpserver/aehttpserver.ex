defmodule Aehttpserver do
  @moduledoc """
  Contains the Aehttpserver application initialization settings
  """

  use Application
  require Logger

  def start(_type, _args) do
    children = [
      Aehttpserver.Web.Endpoint
    ]

    environment_or_generate_authentication()

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  def environment_or_generate_authentication do
    env_authorization = System.get_env("NODE_AUTHORIZATION")

    case env_authorization do
      nil ->
        gen_authorization = UUID.uuid4()
        Application.put_env(:aecore, :authorization, gen_authorization)
        Logger.info(fn -> "Authorization header for /node routes: #{gen_authorization}" end)

      env ->
        Application.put_env(:aecore, :authorization, env)
    end
  end
end
