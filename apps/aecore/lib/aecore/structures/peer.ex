defmodule Aecore.Structures.Peer do
  @moduledoc """
  TODO
  """
  use GenServer
  alias Aecore.Structures.Peer

	defstruct uri: nil,
            last_seen: 0
	use ExConstructor

	def create do
	  new(%{})
	end

	def is_peer?(%Peer{}) do
	  :true
	end
	def is_peer?(_) do
	  :false
	end
end
