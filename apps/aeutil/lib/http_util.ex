defmodule Aeutil.HTTPUtil do
  alias Phoenix.Controller
  alias Plug.Conn

  def json_bad_request(conn, message) do
    set_conn_status_message(conn, 400, message)
  end

  def json_not_found(conn, message) do
    set_conn_status_message(conn, 404, message)
  end

  defp set_conn_status_message(conn, status, message) do
    Controller.json(Conn.put_status(conn, status), %{reason: message})
  end
end
