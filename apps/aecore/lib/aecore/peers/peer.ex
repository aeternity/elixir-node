defmodule Aecore.Peers.Peer do
  defstruct [:pubkey, :host, :port, :connection, :retries, :timer_tref, :trusted]
  use ExConstructor
end
