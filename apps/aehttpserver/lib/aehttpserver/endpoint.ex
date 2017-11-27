defmodule Aehttpserver.Endpoint do
  use Phoenix.Endpoint, otp_app: :aehttpserver

  socket "/socket", Aehttpserver.UserSocket

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :aehttpserver, gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Poison

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_aehttpserver_key",
    signing_salt: "EB5YKhDy"

  plug Aehttpserver.Router

  # def on_response(status, headers, _body, request) do
  #   {status, List.keyreplace(headers, "server", 0, {"server", "aehttpserver"}), request}
  # end
end
