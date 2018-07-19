defmodule Aeutil.Serializable do
  @moduledoc """
  Behaviour that defines functions necessery for structure serialization
  """
  @type error :: {:error, String.t()}

  # Callbacks

  @doc "Takes version and list from rlp encoding, returns decoded structure or error"
  @callback decode_from_list(integer(), list()) :: {:ok, map()} | error()

  @doc "Encodes structure to list for RLP encoding with version prepended but not tag"
  @callback encode_to_list(map()) :: list()
end
