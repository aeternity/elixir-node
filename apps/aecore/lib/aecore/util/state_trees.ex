defmodule Aecore.Util.StateTrees do
  alias Aecore.Account.AccountStateTree
  alias Aecore.Contract.CallStateTree
  alias Aecore.Contract.ContractStateTree
  alias Aecore.Channel.ChannelStateTree
  alias Aecore.Naming.NamingStateTree

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
        PatriciaMerkleTree.new(StateTrees.tree_type(__MODULE__))
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

            case deserialized_value do
              %Name{} ->
                hash = Identifier.create_identity(key, :name)
                %Name{deserialized_value | hash: hash}

              %NameCommitment{} ->
                hash = Identifier.create_identity(key, :commitment)
                %NameCommitment{deserialized_value | hash: hash}

              %Contract{} ->
                identified_id = Identifier.create_identity(key, :contract)
                store_id = Contract.store_id(%{deserialized_value | id: identified_id})

                %Contract{
                  deserialized_value
                  | id: identified_id,
                    store: ContractStateTree.get_store(store_id, tree)
                }

              _ ->
                deserialized_value
            end

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

  # New tree definitions should be described and handled here
  def tree_type(AccountStateTree), do: :accounts
  def tree_type(NamingStateTree), do: :naming
  def tree_type(ChannelStateTree), do: :channels
  def tree_type(ContractStateTree), do: :contracts
  def tree_type(CallStateTree), do: :calls
  def tree_type(unknown_type), do: {:error, "#{__MODULE__}: Invalid tree type: #{unknown_type}"}
end
