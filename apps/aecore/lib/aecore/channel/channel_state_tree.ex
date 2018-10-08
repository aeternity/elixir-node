defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Channel.ChannelStateOnChain
  alias MerklePatriciaTree.Trie

  @type channel_state :: Trie.t()

  @type t :: channel_state()

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
