defmodule Aecore.Util.StateTrees do
  @moduledoc """
  Module defining functions for all Trees
  """
  defmacro __using__(_) do
    quote location: :keep do
      # @behaviour Aecore.Util.StateTrees

      alias MerklePatriciaTree.Trie
      alias Aeutil.PatriciaMerkleTree
      alias Aeutil.Serialization

      @spec init_empty() :: Trie.t()
      def init_empty() do
        PatriciaMerkleTree.new(__MODULE__.name())
      end

      @spec put(Trie.t(), binary(), map()) :: Trie.t()
      def put(tree, key, value) do
        serialized_state = Serialization.rlp_encode(value)
        PatriciaMerkleTree.enter(tree, key, serialized_state)
      end

      @spec root_hash(Trie.t()) :: binary()
      def root_hash(tree) do
        PatriciaMerkleTree.root_hash(tree)
      end

      @spec has_key?(Trie.t(), binary()) :: boolean()
      def has_key?(tree, key) do
        PatriciaMerkleTree.lookup(tree, key) != :none
      end

      @spec delete(Trie.t(), binary()) :: Trie.t()
      def delete(tree, key) do
        PatriciaMerkleTree.delete(tree, key)
      end

      # defoverridable rlp_encode: 1, rlp_decode: 1
    end
  end
end
