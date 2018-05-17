defmodule Aecore.Channel.ChannelStateOffChain do
  @moduledoc """
  Structure of OffChain Channel State
  """

  alias Aecore.Channel.ChannelStateOffChain
  alias Aewallet.Signing
  alias Aeutil.Serialization

  @type t :: %ChannelStateOffChain{
    channel_id: binary(),
    sequence: non_neg_integer(),
    initiator_amount: non_neg_integer(),
    responder_amount: non_neg_integer(),
    signatures: list(binary())
  }

  defstruct [
    :channel_id,
    :sequence,
    :initiator_amount,
    :responder_amount,
    :signatures
  ]

  use ExConstructor

  @spec create(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: Header
  def create(channel_id, sequence, initiator_amount, responder_amount) do
    %ChannelStateOffChain{
      channel_id: channel_id,
      sequence: sequence,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      signatures: [nil, nil]
    }
  end

  def id(%ChannelStateOffChain{channel_id: channel_id}) do channel_id end

  def sequence(%ChannelStateOffChain{sequence: sequence}) do sequence end

  def initiator_amount(%ChannelStateOffChain{initiator_amount: initiator_amount}) do initiator_amount end
  
  def responder_amount(%ChannelStateOffChain{responder_amount: responder_amount}) do responder_amount end

  def validate(%ChannelStateOffChain{signatures: [_, _]} = state, [initiator_pubkey, responder_pubkey]) do
    cond do
      !valid_initiator?(state, initiator_pubkey) ->
        {:error, "Invalid initiator signature"}

      !valid_responder?(state, responder_pubkey) ->
        {:error, "Invalid responder signature"}

      true ->
        :ok
    end
  end
    
  def validate(%ChannelStateOffChain{}, _) do
    {:error, "Invalid signatures count"}
  end

  def validate_half_update(prev_state, new_state, [initiator_pubkey, responder_pubkey], role) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "Different channel id"}

      prev_state.initiator_amount + prev_state.responder_amount 
      != new_state.initiator_amount + new_state.responder_amount ->
        {:error, "Invalid new total amount"}

      role == :initiator && (!valid_responder?(new_state, responder_pubkey)) ->
        {:error, "Invalid responder signature"}

      role == :initiator && prev_state.initiator_amount > new_state.initiator_amount ->
        {:error, "Negative responder trasnfer"}

      role == :responder && (!valid_initiator?(new_state, initiator_pubkey)) ->
        {:error, "Invalid initiator signature"}

      role == :responder && prev_state.responder_amount > new_state.responder_amount ->
        {:error, "Negative initiator trasnfer"}

      true ->
        :ok
    end
  end

  def validate_full_update(prev_state, new_state, pubkeys) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "Different channel id"}
        
      prev_state.initiator_amount + prev_state.responder_amount 
      != new_state.initiator_amount + new_state.responder_amount ->
        {:error, "Invalid new total amount"}

      true ->
        validate(new_state, pubkeys)
    end
  end

  def valid_initiator?(%ChannelStateOffChain{signatures: [initiator_sig, _]} = state, initiator_pubkey) do
    binary_form = signing_form(state)
    Signing.verify(binary_form, initiator_sig, initiator_pubkey)
  end

  def valid_initiator?(%ChannelStateOffChain{}, _) do
    false
  end

  def valid_responder?(%ChannelStateOffChain{signatures: [_, responder_sig]} = state, responder_pubkey) do
    binary_form = signing_form(state)
    Signing.verify(binary_form, responder_sig, responder_pubkey)
  end

  def valid_responder?(%ChannelStateOffChain{}, _) do
    false
  end

  def equal?(state1, state2) do
    state1.channel_id == state2.channel_id
    && state1.initiator_amount == state2.initiator_amount
    && state1.responder_amount == state2.responder_amount
    && state1.sequence == state2.sequence
  end

  def sign(%ChannelStateOffChain{signatures: [nil, responder_sig]} = state, :initiator, priv_key) do
    initiator_sig =
      state
      |> signing_form()
      |> Signing.sign(priv_key)
    %ChannelStateOffChain{state | signatures: [initiator_sig, responder_sig]}
  end

  def sign(%ChannelStateOffChain{signatures: [initiator_sig, nil]} = state, :responder, priv_key) do
    responder_sig =
      state
      |> signing_form()
      |> Signing.sign(priv_key)
    %ChannelStateOffChain{state | signatures: [initiator_sig, responder_sig]}
  end

  def transfer(%ChannelStateOffChain{} = state, :initiator, amount) do
    transfer_amount(state, amount)
  end

  def transfer(%ChannelStateOffChain{} = state, :responder, amount) do
    transfer_amount(state, -amount)
  end

  defp transfer_amount(%ChannelStateOffChain{initiator_amount: initiator_amount, responder_amount: responder_amount, sequence: sequence} = state, amount) do
    new_state = %ChannelStateOffChain{state | 
      initiator_amount: initiator_amount - amount,
      responder_amount: responder_amount + amount,
      sequence: sequence + 1
    }
    {:ok, new_state}
  end

  defp signing_form(%ChannelStateOffChain{} = state) do
    map = %{
      channel_id: state.channel_id,
      initiator_amount: state.initiator_amount,
      responder_amount: state.responder_amount,
      sequence: state.sequence
    }
    Serialization.pack_binary(map)
  end
end
