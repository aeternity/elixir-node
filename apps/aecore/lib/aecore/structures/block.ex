defmodule Aecore.Structures.Block do
  @moduledoc """
  Structure of the block
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @type block() :: %Block{}

  defstruct header: Header.create,
            txs: []
  use ExConstructor

  def create() do
    Block.new(%{})
  end
end
