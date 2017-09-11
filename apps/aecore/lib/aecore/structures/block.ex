defmodule Aecore.Structures.Block do
  @moduledoc """
  Todo
  """
	defstruct height: nil,
            prev_hash: nil,
	          root_hash: nil,
            trees: nil,
            txs: [],
            difficulty: 0,
            nonce: 0,
            time: 0,
            version: 0
	use ExConstructor

  alias Aecore.Structures.Block

  def height(%Block{height: height}) do
	  height
  end

  def trees(%Block{trees: trees}) do
	  trees
  end

  def difficulty(%Block{difficulty: difficulty}) do
	  difficulty
  end

  def set_nonce(block, nonce) do
	  %{block | nonce: nonce}
  end

	def create() do
	  new(%{})
	end

	def is_block?(%Block{}) do
	   :true
	end
	def is_block?(_) do
	  :false
	end
end
