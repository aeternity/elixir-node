defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Channel.ChannelStateOnChain
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @type channel_state :: Trie.t()

  @type t :: channel_state()

  @type hash :: binary()

  @spec name() :: atom()
  def name(), do: :channels

  @spec get(channel_state(), ChannelSteteOnChain.id()) :: :none | ChannelSteteOnChain.t()
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      :none ->
        :none

      {:ok, channel_state_on_chain} ->
        {:ok, channel} = ChannelStateOnChain.rlp_decode(channel_state_on_chain)
        channel
    end
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
end
