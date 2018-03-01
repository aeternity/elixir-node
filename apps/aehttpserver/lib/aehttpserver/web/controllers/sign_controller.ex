defmodule Aehttpserver.Web.SignController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aecore.SigningPrototype.Contract

  def show(conn, params) do
    data = Contract.form_response(params["contract_hash"])
    json(conn, data)
  end
end
