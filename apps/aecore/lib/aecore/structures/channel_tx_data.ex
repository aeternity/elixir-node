defmodule Aecore.Structures.ChannelTxData do

  alias Aecore.Structures.ChannelTxData

  @type channel_tx() :: %ChannelTxData{}

  defstruct [:lock_amounts, :fee]
  use ExConstructor

end
