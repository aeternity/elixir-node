defmodule Aecore.Channel.ChannelStateOffChain do
  @moduledoc """
  Structure of OffChain Channel State
  """

  alias Aecore.Channel.ChannelStateOffChain

  @type t :: %ChannelStateOffChain{
    channel_id: binary(),
    sequence: non_neg_integer(),
    transfer: integer(),
    signatures: list(binary())
  }

  defstruct [
    :channel_id,
    :sequence,
    :transfer,
    :signatures
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
      signatures: [nil, nil]
    }
  end

  def id(%ChannelStateOffChain{channel_id: channel_id}) do channel_id end

  def sequence(%ChannelStateOffChain{sequence: sequence}) do sequence end

  def transfer(%ChannelStateOffChain{transfer: transfer}) do transfer end

  def validate(%ChannelStateOffChain{signatures: [initiator_sig, responder_sig]},
               [initiator_pubkey, responder_pubkey]) do
    :ok #TODO validate signatures
  end

  def validate(%ChannelStateOffChain{}, _) do
    {:error, "Invalid signatures count"}
  end

end
