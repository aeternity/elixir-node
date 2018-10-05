defmodule Aecore.Util.StateTrees do
  @moduledoc """
  Module defining functions for all Trees
  """
  defmacro __using__(_) do
    quote location: :keep do
      # @behaviour Aecore.Util.StateTrees

      alias MerklePatriciaTree.Trie
      alias Aeutil.PatriciaMerkleTree

      @spec init_empty() :: Trie.t()
      def init_empty() do
        PatriciaMerkleTree.new(__MODULE__.name())
      end

      # defoverridable rlp_encode: 1, rlp_decode: 1
    end
  end
end
