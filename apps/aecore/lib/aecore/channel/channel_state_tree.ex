defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  alias Aecore.Channel.ChannelStateOnChain
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie
  alias Aecore.Chain.Identifier

  @type channel_state :: Trie.t()

  @type t :: channel_state()

  @type id :: Identifier.t() | ChannelStateOnChain.id()

  @type hash :: binary()

  @spec init_empty() :: Trie.t()
  def init_empty do
    PatriciaMerkleTree.new(:channels)
  end

  @spec put(channel_state(), id(), ChannelSteteOnChain.t()) :: channel_state()
  def put(tree, key, value) do
    serialized_account_state = ChannelStateOnChain.rlp_encode(value)
    PatriciaMerkleTree.enter(tree, normalize_key(key), serialized_account_state)
  end

  @spec get(channel_state(), id()) :: :none | ChannelStateOnChain.t()
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, normalize_key(key)) do
      :none ->
        :none

      {:ok, channel_state_on_chain} ->
        {:ok, channel} = ChannelStateOnChain.rlp_decode(channel_state_on_chain)
        channel
    end
  end

  @spec delete(channel_state(), id()) :: channel_state()
  def delete(tree, key) do
    PatriciaMerkleTree.delete(tree, normalize_key(key))
  end

  @spec update!(
          channel_state(),
          id(),
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

  @spec has_key?(channel_state(), id()) :: boolean()
  def has_key?(tree, key) do
    PatriciaMerkleTree.lookup(tree, normalize_key(key)) != :none
  end

  @spec root_hash(channel_state()) :: hash()
  def root_hash(tree) do
    PatriciaMerkleTree.root_hash(tree)
  end

  @spec normalize_key(id()) :: ChannelStateOnChain.id()
  def normalize_key(%Identifier{type: :channel, value: key}) do
    key
  end

  def normalize_key(key) when is_binary(key) do
    key
  end
end
