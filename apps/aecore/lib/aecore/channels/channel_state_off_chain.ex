defmodule Aecore.Channel.ChannelStateOffChain do
  @moduledoc """
  Structure of OffChain Channel State
  """

  alias Aecore.Channel.ChannelStateOffChain

  @type t :: %ChannelStateOffChain{
    channel_id: binary(),
    sequence: non_neg_integer(),
    transfer: integer()
  }

  defstruct [
    :channel_id,
    :sequence,
    :transfer
  ]

  use ExConstructor

  @spec create(
          binary(),
          non_neg_integer(),
          integer()
        ) :: Header
  def create(channel_id, sequence, transfer) do
    %ChannelStateOffChain{
      channel_id: channel_id,
      sequence: sequence,
      transfer: transfer
    }
  end
end
