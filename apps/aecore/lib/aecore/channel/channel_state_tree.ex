defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Channel.ChannelStateOnChain
  alias MerklePatriciaTree.Trie

  @typedoc "Channel tree"
  @type channel_state :: Trie.t()

  @type t :: channel_state()

  @spec tree_type :: atom()
  def tree_type, do: :channels

  @spec update!(
          channel_state(),
          ChannelStateOnChain.id(),
          (ChannelStateOnChain.t() -> ChannelStateOnChain.t())
        ) :: channel_state()
  def update!(tree, key, fun) do
    case get(tree, key) do
      :none ->
        throw({:error, "#{__MODULE__}: No such channel"})

      value ->
        put(tree, key, fun.(value))
    end
  end

  @spec process_struct(ChannelSteteOnChain.t(), ChannelSteteOnChain.id(), channel_state()) ::
          ChannelSteteOnChain.t()
  def process_struct(deserialized_value, _key, _tree) do
    deserialized_value
  end
end
