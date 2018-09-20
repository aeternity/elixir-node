defmodule Aecore.Channel.ChannelStateOffChain do
  @moduledoc """
  Module defining the structure of the OffChain Channel state
  """

  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.Worker, as: Channel
  alias Aecore.Keys
  alias Aeutil.Serialization

  @signing_tag 102

  @version 1

  @typedoc "Structure of the ChannelStateOffChain Transaction type"
  @type t :: %ChannelStateOffChain{
          channel_id: binary(),
          sequence: non_neg_integer(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer(),
          signatures: {binary(), binary()}
        }

  @typedoc "Reason for the error"
  @type error :: {:error, binary()}

  defstruct [
    :channel_id,
    :sequence,
    :initiator_amount,
    :responder_amount,
    :signatures
  ]

  use Aecore.Util.Serializable

  require Logger

  @spec create(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: ChannelStateOffChain.t()
  def create(channel_id, sequence, initiator_amount, responder_amount) do
    %ChannelStateOffChain{
      channel_id: channel_id,
      sequence: sequence,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      signatures: {<<>>, <<>>}
    }
  end

  @spec init(map()) :: ChannelStateOffChain.t()
  def init(%{
        channel_id: channel_id,
        sequence: sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        signatures: signatures
      }) do
    %ChannelStateOffChain{
      channel_id: channel_id,
      sequence: sequence,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      signatures: signatures
    }
  end

  @spec total_amount(ChannelStateOffChain.t()) :: non_neg_integer()
  def total_amount(%ChannelStateOffChain{
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    initiator_amount + responder_amount
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelStateOffChain.t(), {Keys.pubkey(), Keys.pubkey()}) :: :ok | error()
  def validate(%ChannelStateOffChain{signatures: {_, _}} = state, {
        initiator_pubkey,
        responder_pubkey
      }) do
    cond do
      !valid_initiator?(state, initiator_pubkey) ->
        {:error, "#{__MODULE__}: Invalid initiator signature"}

      !valid_responder?(state, responder_pubkey) ->
        {:error, "#{__MODULE__}: Invalid responder signature"}

      true ->
        :ok
    end
  end

  def validate(%ChannelStateOffChain{}, _) do
    {:error, "#{__MODULE__}: Invalid signatures count"}
  end

  @doc """
  Validates a half signed update(new object) of ChannelStateOffChain. The update is valid if the transfer is in correct the direction and the sequence has been increased. Role should be the role of validating peer.
  """
  @spec validate_half_update(
          ChannelStateOffChain.t(),
          ChannelStateOffChain.t(),
          {Keys.pubkey(), Keys.pubkey()},
          Channel.role()
        ) :: :ok | error()
  def validate_half_update(prev_state, new_state, {initiator_pubkey, responder_pubkey}, role) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "#{__MODULE__}: Different channel id"}

      prev_state.initiator_amount + prev_state.responder_amount !=
          new_state.initiator_amount + new_state.responder_amount ->
        {:error, "#{__MODULE__}: Invalid new total amount"}

      role == :initiator && !valid_responder?(new_state, responder_pubkey) ->
        {:error, "#{__MODULE__}: Invalid responder signature"}

      role == :initiator && prev_state.initiator_amount > new_state.initiator_amount ->
        {:error, "#{__MODULE__}: Negative responder transfer"}

      role == :responder && !valid_initiator?(new_state, initiator_pubkey) ->
        {:error, "#{__MODULE__}: Invalid initiator signature"}

      role == :responder && prev_state.responder_amount > new_state.responder_amount ->
        {:error, "#{__MODULE__}: Negative initiator transfer"}

      true ->
        :ok
    end
  end

  @doc """
  Validates a new fully signed ChannelStateOffChain.
  """
  @spec validate_full_update(
          ChannelStateOffChain.t(),
          ChannelStateOffChain.t(),
          {Keys.pubkey(), Keys.pubkey()}
        ) :: :ok | error()
  def validate_full_update(prev_state, new_state, pubkeys) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "#{__MODULE__}: Different channel id"}

      prev_state.initiator_amount + prev_state.responder_amount !=
          new_state.initiator_amount + new_state.responder_amount ->
        {:error, "#{__MODULE__}: Invalid new total amount"}

      true ->
        validate(new_state, pubkeys)
    end
  end

  @doc """
  Validates the initiator signature
  """
  @spec valid_initiator?(ChannelStateOffChain.t(), Keys.pubkey()) :: boolean()
  def valid_initiator?(%ChannelStateOffChain{signatures: {<<>>, _}}, _) do
    false
  end

  def valid_initiator?(
        %ChannelStateOffChain{signatures: {initiator_sig, _}} = state,
        initiator_pubkey
      ) do
    binary_form = signing_form(state)
    Keys.verify(binary_form, initiator_sig, initiator_pubkey)
  end

  def valid_initiator?(%ChannelStateOffChain{}, _) do
    Logger.error("#{__MODULE__}: Wrong ChannelStateOffChain signatures structure")
    false
  end

  @doc """
  Validates the responder signature
  """
  @spec valid_responder?(ChannelStateOffChain.t(), Keys.pubkey()) :: boolean()
  def valid_responder?(%ChannelStateOffChain{signatures: {_, <<>>}}, _) do
    false
  end

  def valid_responder?(
        %ChannelStateOffChain{signatures: {_, responder_sig}} = state,
        responder_pubkey
      ) do
    binary_form = signing_form(state)
    Keys.verify(binary_form, responder_sig, responder_pubkey)
  end

  def valid_responder?(%ChannelStateOffChain{}, _) do
    Logger.error("#{__MODULE__}: Wrong ChannelStateOffChain signatures structure")
    false
  end

  @doc """
  Checks if two states are equal. Ignores signatures.
  """
  @spec equal?(ChannelStateOffChain.t(), ChannelStateOffChain.t()) :: boolean()
  def equal?(state1, state2) do
    state1.channel_id == state2.channel_id && state1.initiator_amount == state2.initiator_amount &&
      state1.responder_amount == state2.responder_amount && state1.sequence == state2.sequence
  end

  @doc """
  Signs a state.
  """
  @spec sign(ChannelStateOffChain.t(), Channel.role(), Keys.sign_priv_key()) ::
          ChannelStateOffChain.t()
  def sign(%ChannelStateOffChain{signatures: {_, responder_sig}} = state, :initiator, priv_key) do
    initiator_sig =
      state
      |> signing_form()
      |> Keys.sign(priv_key)

    %ChannelStateOffChain{state | signatures: {initiator_sig, responder_sig}}
  end

  def sign(%ChannelStateOffChain{signatures: {initiator_sig, _}} = state, :responder, priv_key) do
    responder_sig =
      state
      |> signing_form()
      |> Keys.sign(priv_key)

    %ChannelStateOffChain{state | signatures: {initiator_sig, responder_sig}}
  end

  @doc """
  Creates new state with transfer applied. Role is the peer who transfers funds to the other peer.
  """
  @spec transfer(ChannelStateOffChain.t(), Channel.role(), non_neg_integer()) ::
          ChannelStateOffChain.t()
  def transfer(%ChannelStateOffChain{} = state, :initiator, amount) do
    transfer_amount(state, amount)
  end

  def transfer(%ChannelStateOffChain{} = state, :responder, amount) do
    transfer_amount(state, -amount)
  end

  defp transfer_amount(
         %ChannelStateOffChain{
           initiator_amount: initiator_amount,
           responder_amount: responder_amount,
           sequence: sequence
         } = state,
         amount
       ) do
    new_state = %ChannelStateOffChain{
      state
      | initiator_amount: initiator_amount - amount,
        responder_amount: responder_amount + amount,
        sequence: sequence + 1,
        signatures: {<<>>, <<>>}
    }

    {:ok, new_state}
  end

  defp signing_form(%ChannelStateOffChain{
         channel_id: channel_id,
         initiator_amount: initiator_amount,
         responder_amount: responder_amount,
         sequence: sequence
       }) do
    list_form = [
      :binary.encode_unsigned(@signing_tag),
      :binary.encode_unsigned(@version),
      channel_id,
      :binary.encode_unsigned(initiator_amount),
      :binary.encode_unsigned(responder_amount),
      :binary.encode_unsigned(sequence)
    ]

    ExRLP.encode(list_form)
  end

  @spec encode_to_list(ChannelStateOffChain.t()) :: list()
  def encode_to_list(%ChannelStateOffChain{
        channel_id: channel_id,
        sequence: sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        signatures: {initiator_sig, responder_sig}
      }) do
    [
      :binary.encode_unsigned(@version),
      channel_id,
      :binary.encode_unsigned(sequence),
      :binary.encode_unsigned(initiator_amount),
      :binary.encode_unsigned(responder_amount),
      [initiator_sig, responder_sig]
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, ChannelStateOffChain.t()} | error()
  def decode_from_list(@version, [
        channel_id,
        sequence,
        initiator_amount,
        responder_amount,
        [initiator_sig, responder_sig]
      ]) do
    {:ok,
     %ChannelStateOffChain{
       channel_id: channel_id,
       sequence: :binary.decode_unsigned(sequence),
       initiator_amount: :binary.decode_unsigned(initiator_amount),
       responder_amount: :binary.decode_unsigned(responder_amount),
       signatures: {initiator_sig, responder_sig}
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
