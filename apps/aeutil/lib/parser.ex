defmodule Aeutil.Parser do
  @moduledoc """
  Parses different types of data
  """

  def to_atom!(key) when is_atom(key), do: key
  def to_atom!(key) when is_binary(key), do: String.to_atom(key)
  def to_atom!(_key), do: throw("Key is neither atom nor string")

  def to_string!(key) when is_binary(key), do: key
  def to_string!(key) when is_atom(key), do: Atom.to_string(key)
  def to_string!(_key), do: throw("Key is neither atom nor string")

end
