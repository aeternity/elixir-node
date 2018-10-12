defmodule Aecore.Util.StateTrees do
  @moduledoc """
  Abstract module defining functions for known Tree types
  """
  alias MerklePatriciaTree.Trie

  defmacro __using__([tree_type, stored_type]) when is_atom(tree_type) do
    quote location: :keep do
      @behaviour Aecore.Util.StateTrees

      alias Aecore.Account.Account
      alias Aecore.Contract.{Call, Contract, ContractStateTree}
      alias Aecore.Chain.Identifier
      alias Aecore.Naming.{Name, NameCommitment}
      alias Aecore.Channel.ChannelStateOnChain
      alias Aecore.Util.StateTrees
      alias Aeutil.PatriciaMerkleTree
      alias Aeutil.Serialization
      alias MerklePatriciaTree.Trie

      @typedoc "Hash of the tree"
      @type hash :: binary()

      @spec init_empty :: Trie.t()
      def init_empty do
        PatriciaMerkleTree.new(unquote(tree_type))
      end

      @spec put(
              Trie.t(),
              binary(),
              ChannelStateOnChain.t()
              | Contract.t()
              | Call.t()
              | Name.t()
              | NameCommitment.t()
              | Account.t()
            ) :: Trie.t() | {:error, String.t()}
      def put(tree, key, value) do
        if StateTrees.valid_store_type?(value, unquote(stored_type)) do
          serialized_state = Serialization.rlp_encode(value)
          PatriciaMerkleTree.enter(tree, key, serialized_state)
        else
          {:error,
           "#{__MODULE__}: Invalid value type: #{value.__struct__} but expected value type #{
             unquote(stored_type)
           }"}
        end
      end

      @spec get(Trie.t(), binary()) ::
              ChannelStateOnChain.t()
              | Contract.t()
              | Call.t()
              | Name.t()
              | NameCommitment.t()
              | :none
              | {:error, String.t()}
      def get(tree, key) do
        with {:ok, serialized_value} <- PatriciaMerkleTree.lookup(tree, key),
             {:ok, deserialized_value} <- Serialization.rlp_decode_anything(serialized_value),
             true <- StateTrees.valid_store_type?(deserialized_value, unquote(stored_type)) do
          __MODULE__.process_struct(deserialized_value, key, tree)
        else
          :none ->
            :none

          false ->
            {:error, "#{__MODULE__}: Invalid struct type, expected #{unquote(stored_type)}"}

          _ ->
            {:error, "#{__MODULE__}: Illegal function call"}
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

      @spec update(Trie.t(), binary(), fun()) :: Trie.t()
      def update(tree, key, fun) do
        put(tree, key, fun.(get(tree, key)))
      end

      @spec delete(Trie.t(), binary()) :: Trie.t()
      def delete(tree, key) do
        PatriciaMerkleTree.delete(tree, key)
      end

      # If the functions are implemented in a module they will be overwritten
      defoverridable get: 2, update: 3
    end
  end

  # Callbacks
  @doc "Takes structure, key and tree. Returns structure or error"
  @callback process_struct(map(), binary(), Trie.t()) :: map() | {:error, String.t()}

  @spec valid_store_type?(map(), atom() | list()) :: boolean()
  def valid_store_type?(deserialized_value, store_type) when is_atom(store_type) do
    deserialized_value.__struct__ == store_type
  end

  def valid_store_type?(deserialized_value, store_type) when is_list(store_type) do
    deserialized_value.__struct__ in store_type
  end
end
