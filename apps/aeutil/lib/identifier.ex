defmodule Aeutil.Identifier do
  alias Aeutil.Identifier

  @moduledoc """
  Utility module for interacting with identifiers. 

  """
  defstruct [:type, :value]
  use ExConstructor
  @type type() :: :account | :name | :commitment | :oracle | :contract | :channel
  @type id() :: non_neg_integer()
  @type value() :: binary()
  @type t() :: %Identifier{type: type(), value: value()}

  @spec create_identifier(type(), id()) :: Identifier.t()
  def create_identifier(tag, id) do
  end
end
