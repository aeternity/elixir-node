defmodule Aecore.Channel.ChannelOffchainTx do
  @moduledoc """
  Structure of OffChain Channel Transaction
  """

  alias Aecore.Channel.ChannelOffchainTx
  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.Worker, as: Channel
  alias Aecore.Keys
  alias Aeutil.Serialization
  alias Aeutil.TypeToTag
  alias Aecore.Chain.Identifier

  @version 1
  @signed_tx_tag 11 #TypeToTag.type_to_tag(Aecore.Tx.SignedTx)

  @type t :: %ChannelOffchainTx{
          channel_id: Identifier.t(),
          sequence:   non_neg_integer(),
          updates:    list(ChannelOffchainUpdate.update_types()),
          state_hash: binary(),
          signatures: {binary(), binary()}
        }

  @type error :: {:error, binary()}

  @doc """
  Definition of Aecore ChannelOffchainTx structure

  ## Parameters
  - channel_id: ID of the channel
  - sequence:   Number of the update round
  - updates:    List of updates to the offchain chainstate
  - state_hash: Root hash of the offchain chainstate after applying the updates
  - signatures: Initiator/Responder signatures of the offchain transaction
  """
  defstruct [
    :channel_id,
    :sequence,
    :updates,
    :state_hash,
    :signatures
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  require Logger

  @spec create(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: ChannelOffchainTx.t()
  def create(channel_id, sequence, initiator_amount, responder_amount) do
    %ChannelOffchainTx{
      channel_id: channel_id,
      sequence: sequence,
      signatures: {<<>>, <<>>}
    }
  end

  @spec init(map()) :: ChannelOffChainTx.t()
  def init(%{
        channel_id: channel_id,
        sequence: sequence,
        signatures: signatures
      }) do
    %ChannelOffchainTx{
      channel_id: channel_id,
      sequence: sequence,
      signatures: signatures
    }
  end

  @doc """
  Validates ChannelStateOffChain signatures.
  """
  @spec validate(ChannelOffchainTx.t(), {Keys.pubkey(), Keys.pubkey()}) :: :ok | error()
  def validate(%ChannelOffchainTx{signatures: {_, _}} = state, {
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

  def validate(%ChannelOffchainTx{}, _) do
    {:error, "#{__MODULE__}: Invalid signatures count"}
  end

  @doc """
  Validates half signed update(new object) of ChannelStateOffChain. Updates validates if transfer is in correct direction and sequence is increasing. Role should be the role of validating peer.
  """
  @spec validate_half_update(
          ChannelOffchainTx.t(),
          ChannelOffchainTx.t(),
          {Keys.pubkey(), Keys.pubkey()},
          Channel.role()
        ) :: :ok | error()
  def validate_half_update(prev_state, new_state, {initiator_pubkey, responder_pubkey}, role) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "#{__MODULE__}: Different channel id"}

      role == :initiator && !valid_responder?(new_state, responder_pubkey) ->
        {:error, "#{__MODULE__}: Invalid responder signature"}

      role == :responder && !valid_initiator?(new_state, initiator_pubkey) ->
        {:error, "#{__MODULE__}: Invalid initiator signature"}


      true ->
        :ok
    end
  end

  @doc """
  Validates new fully signed ChannelStateOffChain.
  """
  @spec validate_full_update(
          ChannelOffchainTx.t(),
          ChannelOffchainTx.t(),
          {Keys.pubkey(), Keys.pubkey()}
        ) :: :ok | error()
  def validate_full_update(prev_state, new_state, pubkeys) do
    cond do
      new_state.sequence <= prev_state.sequence ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      new_state.channel_id != prev_state.channel_id ->
        {:error, "#{__MODULE__}: Different channel id"}

      true ->
        validate(new_state, pubkeys)
    end
  end

  @doc """
  Validates initiator signature
  """
  @spec valid_initiator?(ChannelOffchainTx.t(), Keys.pubkey()) :: boolean()
  def valid_initiator?(%ChannelOffchainTx{signatures: {<<>>, _}}, _) do
    false
  end

  def valid_initiator?(
        %ChannelOffchainTx{signatures: {initiator_sig, _}} = state,
        initiator_pubkey
      ) do
    binary_form = Serialization.rlp_encode(state)
    Keys.verify(binary_form, initiator_sig, initiator_pubkey)
  end

  def valid_initiator?(%ChannelOffchainTx{}, _) do
    Logger.error("#{__MODULE__}: Wrong ChannelStateOffChain signatures structure")
    false
  end

  @doc """
  Validates responder signature
  """
  @spec valid_responder?(ChannelOffchainTx.t(), Keys.pubkey()) :: boolean()
  def valid_responder?(%ChannelOffchainTx{signatures: {_, <<>>}}, _) do
    false
  end

  def valid_responder?(
        %ChannelOffchainTx{signatures: {_, responder_sig}} = state,
        responder_pubkey
      ) do
    binary_form = Serialization.rlp_encode(state)
    Keys.verify(binary_form, responder_sig, responder_pubkey)
  end

  def valid_responder?(%ChannelOffchainTx{}, _) do
    Logger.error("#{__MODULE__}: Wrong ChannelOffchainTx signatures structure")
    false
  end

  @doc """
  Checks is two states are equal. Ignores signatures.
  """
  @spec equal?(ChannelOffchainTx.t(), ChannelOffchainTx.t()) :: boolean()
  def equal?(state1, state2) do
    state1.channel_id == state2.channel_id && state1.sequence == state2.sequence
  end

  @doc """
  Signs a state.
  """
  @spec sign(ChannelOffchainTx.t(), Channel.role(), Keys.sign_priv_key()) ::
          ChannelOffchainTx.t()
  def sign(%ChannelOffchainTx{signatures: {_, responder_sig}} = state, :initiator, priv_key) do
    initiator_sig =
      state
      |> Serialization.rlp_encode()
      |> Keys.sign(priv_key)

    %ChannelOffchainTx{state | signatures: {initiator_sig, responder_sig}}
  end

  def sign(%ChannelOffchainTx{signatures: {initiator_sig, _}} = state, :responder, priv_key) do
    responder_sig =
      state
      |> Serialization.rlp_encode()
      |> Keys.sign(priv_key)

    %ChannelOffchainTx{state | signatures: {initiator_sig, responder_sig}}
  end

  @doc """
  Creates new state with transfer applied. Role is the peer who transfer to other peer.
  """
  @spec transfer(ChannelOffchainTx.t(), Channel.role(), non_neg_integer()) ::
          ChannelOffchainTx.t()
  def transfer(%ChannelOffchainTx{} = state, :initiator, amount) do
    transfer_amount(state, <<>>, <<>>, amount)
  end

  def transfer(%ChannelOffchainTx{} = state, :responder, amount) do
    transfer_amount(state, <<>>, <<>>, -amount)
  end

  defp transfer_amount(
         %ChannelOffchainTx{
           sequence: sequence
         } = state,
          initiator_pubkey,
          responder_pubkey,
          amount
       ) do
    new_state = %ChannelOffchainTx{
      state
      | updates: [ChannelTransferUpdate.new(initiator_pubkey, responder_pubkey, amount)],
        sequence: sequence + 1,
        signatures: {<<>>, <<>>}
    }

    {:ok, new_state}
  end

  def encode_to_payload(%ChannelOffchainTx{signatures: {initiator_sig, responder_sig}} = state) do
    [
      :binary.encode_unsigned(@signed_tx_tag),
      :binary.encode_unsigned(@version),
      [initiator_sig, responder_sig],
      Serialization.rlp_encode(state)
    ]
    |> ExRLP.encode
  end

  def decode_from_payload([@signed_tx_tag, @version, [initiator_sig, responder_sig], encoded_tx]) do
    decoded_tx = Serialization.rlp_decode(encoded_tx, ChannelOffchainTx)
    %ChannelOffchainTx{decoded_tx | signatures: {initiator_sig, responder_sig}}
  end

  def decode_from_payload([[@signed_tx_tag, @version] | _]) do
    {:error, "#{__MODULE__}: decode_from_payload: Invalid serialization"}
  end

  def decode_from_payload([@signed_tx_tag | version]) do
    {:error, "#{__MODULE__}: decode_from_payload: Unknown version #{version}"}
  end

  def decode_from_payload([tag | _]) do
    {:error, "#{__MODULE__}: decode_from_payload: Invalid payload tag #{tag}"}
  end

  def encode_to_list(%ChannelOffchainTx{
    channel_id: %Identifier{type: :channel} = channel_id,
    sequence:   sequence,
    updates:    updates,
    state_hash: state_hash
  }, _datatx) do
    encoded_updates = Enum.map(updates, &ChannelOffchainUpdate.to_list/1)
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(channel_id),
      :binary.encode_unsigned(sequence),
      encoded_updates,
      state_hash
    ]
  end

  def decode_from_list(@version, [
        channel_id,
        sequence,
        encoded_updates,
        state_hash
      ]) do
    %ChannelOffchainTx{
      channel_id: Identifier.decode_from_binary(channel_id),
      sequence: :binary.decode_unsigned(sequence),
      updates: Enum.map(encoded_updates, &ChannelOffchainUpdate.from_list/1),
      state_hash: state_hash
    }
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
