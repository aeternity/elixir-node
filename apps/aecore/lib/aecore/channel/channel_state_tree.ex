defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  alias Aecore.Channel.ChannelStateOnChain
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @type channel_state :: Trie.t()

  @type t :: channel_state()

  @type hash :: binary()

  @spec init_empty() :: Trie.t()
  def init_empty do
    PatriciaMerkleTree.new(:channels)
  end

  @spec put(channel_state(), ChannelSteteOnChain.id(), ChannelSteteOnChain.t()) :: channel_state()
  def put(trie, key, value) do
    serialized_account_state = Serialization.rlp_encode(value)
    PatriciaMerkleTree.enter(trie, key, serialized_account_state)
  end

  @spec get(channel_state(), ChannelSteteOnChain.id()) :: :none | ChannelSteteOnChain.t()
  def get(trie, key) do
    case PatriciaMerkleTree.lookup(trie, key) do
      :none ->
        :none

      {:ok, channel_state_on_chain} ->
        {:ok, channel} = ChannelStateOnChain.rlp_decode(channel_state_on_chain)

        channel
    end
  end

  @spec delete(channel_state(), ChannelStateOnChain.id()) :: channel_state()
  def delete(trie, key) do
    PatriciaMerkleTree.delete(trie, key)
  end

  @spec update!(
          channel_state(),
          ChannelSteteOnChain.id(),
          (ChannelSteteOnChain.t() -> ChannelSteteOnChain.t())
        ) :: channel_state()
  def update!(tree, key, fun) do
    case get(tree, key) do
      :none ->
        throw({:error, "#{__MODULE__}: No such channel"})

      value ->
        put(tree, key, fun.(value))
    end
  end

  @spec has_key?(channel_state(), ChannelSteteOnChain.id()) :: boolean()
  def has_key?(trie, key) do
    PatriciaMerkleTree.lookup(trie, key) != :none
  end

  @spec root_hash(channel_state()) :: hash()
  def root_hash(trie) do
    PatriciaMerkleTree.root_hash(trie)
  end
end
