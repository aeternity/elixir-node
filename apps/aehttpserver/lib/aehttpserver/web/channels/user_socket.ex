defmodule Aehttpserver.Web.UserSocket do
  use Phoenix.Socket

  channel "room:*", Aehttpserver.Web.NotificationChannel

  transport :websocket, Phoenix.Transports.WebSocket

  def connect(_params, socket) do
    {:ok, socket}
  end

  def id(_socket), do: nil

end
