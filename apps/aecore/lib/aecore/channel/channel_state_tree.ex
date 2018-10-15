defmodule Aecore.Channel.ChannelStateTree do
  @moduledoc """
  Top level channel state tree.
  """
  use Aecore.Util.StateTrees, [:channels, Aecore.Channel.ChannelStateOnChain]

  alias Aecore.Channel.ChannelStateOnChain
  alias MerklePatriciaTree.Trie

  @typedoc "Channel tree"
  @type channel_state :: Trie.t()

  @type t :: channel_state()

  @spec update!(
          channel_state(),
          binary(),
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

  @spec process_struct(ChannelStateOnChain.t(), ChannelStateOnChain.id(), channel_state()) ::
          ChannelStateOnChain.t() | {:error, String.t()}
  def process_struct(%ChannelStateOnChain{} = deserialized_value, _key, _tree) do
    deserialized_value
  end

  def process_struct(deserialized_value, _key, _tree) do
    {:error,
     "#{__MODULE__}: Invalid data type: #{deserialized_value.__struct__} but expected %ChannelStateOnChain{}"}
  end
end
