defmodule Aecore.Structures.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Structures.Header

  defstruct height: 0,
            prev_hash: nil,
            txs_hash: nil,
            difficulty_target: 0,
            nonce: 0,
            timestamp: 0,
            version: 1
  use ExConstructor

  @type header() :: %Header{}

  def create do
    Header.new(%{})
  end
end
