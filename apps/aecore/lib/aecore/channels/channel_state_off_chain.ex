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

  def validate(%ChannelStateOffChain{signatures: [initiator_sig, responder_sig]}) do
    :ok #TODO validate signatures
  end

  def validate(%ChannelStateOffChain{}) do
    {:error, "Invalid signatures count"}
  end


end
