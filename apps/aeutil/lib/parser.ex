defmodule Aeutil.Parser do
  @moduledoc """
  Parses different types of data
  """

  def to_atom(key) when is_atom(key), do: key
  def to_atom(key) when is_binary(key), do: String.to_atom(key)
  def to_atom(key), do: key

  def to_string(key) when is_binary(key), do: key
  def to_string(key) when is_atom(key), do: Atom.to_string(key)
  def to_string(key), do: key
end
