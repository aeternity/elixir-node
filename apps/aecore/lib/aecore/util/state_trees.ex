defmodule Aecore.Util.StateTrees do
  alias Aecore.Contract.CallStateTree
  alias Aecore.Channel.ChannelStateTree
  alias Aecore.Contract.ContractStateTree
  alias Aecore.Naming.NamingStateTree
  alias Aecore.Account.AccountStateTree

  @moduledoc """
  Module defining functions for all Trees
  """
  defmacro __using__(_) do
    quote location: :keep do
      # @behaviour Aecore.Util.StateTrees

      alias MerklePatriciaTree.Trie
      alias Aeutil.PatriciaMerkleTree
      alias Aeutil.Serialization
      alias Aecore.Util.StateTrees

      @spec init_empty() :: Trie.t()
      def init_empty() do
        PatriciaMerkleTree.new(StateTrees.tree_type(__MODULE__))
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

  # New tree definitions should be described and handled here
  def tree_type(AccountStateTree), do: :accounts
  def tree_type(NamingStateTree), do: :naming
  def tree_type(ChannelStateTree), do: :channels
  def tree_type(ContractStateTree), do: :contracts
  def tree_type(CallStateTree), do: :calls
  # def tree_type(), do: :txs
  # def tree_type(), do: :proof
  # def tree_type(), do: :oracles
  # def tree_type(), do: :oracles_cache
  def tree_type(unknown_type), do: {:error, "#{__MODULE__}: Invalid tree type: #{unknown_type}"}
end
