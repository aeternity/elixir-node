defmodule Aecore.Structures.Header do
	defstruct height: nil,
            prev_hash: nil,
            root_hash: nil,
            difficulty: 0,
            nonce: 0,
            time: 0,
            version: 0
	use ExConstructor
	alias Aecore.Structures.Header

	def create do
	  Header.new(%{})
	end

	def is_header?(%Header{}) do
	  :true
	end
	def is_header?(_) do
	  :false
	end

end
