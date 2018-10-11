defmodule Aecore.Util.StateTrees do
  @moduledoc """
  Abstract module defining functions for known Tree types
  """
  defmacro __using__(_) do
    quote location: :keep do
      alias Aecore.Contract.{Contract, ContractStateTree}
      alias Aecore.Chain.Identifier
      alias Aecore.Naming.{Name, NameCommitment}
      alias Aecore.Util.StateTrees
      alias Aeutil.PatriciaMerkleTree
      alias Aeutil.Serialization
      alias MerklePatriciaTree.Trie

      @typedoc "Hash of the tree"
      @type hash :: binary()

      @spec init_empty :: Trie.t()
      def init_empty do
        PatriciaMerkleTree.new(__MODULE__.tree_type())
      end

      @spec put(Trie.t(), binary(), map()) :: Trie.t()
      def put(tree, key, value) do
        serialized_state = Serialization.rlp_encode(value)
        PatriciaMerkleTree.enter(tree, key, serialized_state)
      end

      @spec get(Trie.t(), binary()) :: :none | map()
      def get(tree, key) do
        case PatriciaMerkleTree.lookup(tree, key) do
          {:ok, serialized_value} ->
            {:ok, deserialized_value} = Serialization.rlp_decode_anything(serialized_value)
            __MODULE__.process_struct(deserialized_value, key, tree)

          :none ->
            :none
        end
      end

      @spec root_hash(Trie.t()) :: hash()
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

      defoverridable get: 2
    end
  end
end
