defmodule Aecore.Channel.ChannelOffchainTx do
  @moduledoc """
  Structure of an Offchain Channel Transaction. Implements a cryptographically signed  container for channel updates associated with an offchain chainstate.
  """

  alias Aecore.Channel.ChannelOffchainTx
  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Channel.ChannelTransaction
  alias Aecore.Keys
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

  @behaviour ChannelTransaction

  @version 1
  @signed_tx_tag 11 #TypeToTag.type_to_tag(Aecore.Tx.SignedTx)

  @typedoc """
  Structure of the ChannelOffchainTx type
  """
  @type t :: %ChannelOffchainTx{
          channel_id: Identifier.t(),
          sequence:   non_neg_integer(),
          updates:    list(ChannelOffchainUpdate.update_types()),
          state_hash: binary(),
          signatures: {binary(), binary()}
        }

  @typedoc """
  The type of errors returned by the functions in this module
  """
  @type error :: {:error, String.t()}

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

  @doc """
  Validates the signatures under the offchain transaction.
  """
  @spec validate(ChannelOffchainTx.t(), {Keys.pubkey(), Keys.pubkey()}) :: :ok | error()
  def validate(%ChannelOffchainTx{signatures: {_, _}} = state, {
        initiator_pubkey,
        responder_pubkey
      }) do
    cond do
      !signature_valid_for?(state, initiator_pubkey) ->
        {:error, "#{__MODULE__}: Invalid initiator signature"}

      !signature_valid_for?(state, responder_pubkey) ->
        {:error, "#{__MODULE__}: Invalid responder signature"}

      true ->
        :ok
    end
  end

  def validate(%ChannelOffchainTx{}, _) do
    {:error, "#{__MODULE__}: Invalid signatures count"}
  end

  @doc """
  Checks if there is a signature for the specified pubkey.
  """
  @spec signature_valid_for?(ChannelOffchainTx.t(), Keys.pubkey()) :: boolean()
  def signature_valid_for?(%ChannelOffchainTx{signatures: {<<>>, _}}, _) do
    false
  end

  def signature_valid_for?(
        %ChannelOffchainTx{signatures: {sig1, sig2}} = state,
        pubkey
      ) do
    binary_form = Serialization.rlp_encode(state)
    Keys.verify(binary_form, sig1, pubkey) or signature_valid_for?(%ChannelOffchainTx{state | signatures: {sig2, <<>>}}, pubkey)
  end

  @spec signature_for_offchain_tx(ChannelOffchainTx.t(), Keys.sign_priv_key()) :: binary()
  defp signature_for_offchain_tx(%ChannelOffchainTx{} = offchain_tx, priv_key) when is_binary(priv_key) do
    offchain_tx
    |> Serialization.rlp_encode()
    |> Keys.sign(priv_key)
  end

  @doc """
  Signs the offchain transaction with the provided private key.
  """
  @spec sign_with(ChannelOffchainTx.t(), Keys.sign_priv_key()) ::
          ChannelOffchainTx.t()
  def sign_with(%ChannelOffchainTx{signatures: {<<>>, <<>>}} = offchain_tx, priv_key) do
    sig = signature_for_offchain_tx(offchain_tx, priv_key)

    {:ok, %ChannelOffchainTx{offchain_tx | signatures: {sig, <<>>}}}
  end

  def sign_with(%ChannelOffchainTx{signatures: {sig1, <<>>}} = offchain_tx, priv_key) do
    sig2 = signature_for_offchain_tx(offchain_tx, priv_key)

    if sig2 > sig1 do
      {:ok, %ChannelOffchainTx{offchain_tx | signatures: {sig1, sig2}}}
    else
      {:ok, %ChannelOffchainTx{offchain_tx | signatures: {sig2, sig1}}}
    end
  end

  @doc """
  Creates a new offchain transaction containing an transfer update between the specified accounts.
  The resulting offchain transaction is not tied to any offchain chainstate.
  """
  @spec initialize_transfer(Identifier.t(), Keys.pubkey(), Keys.pubkey(), non_neg_integer()) :: ChannelOffchainTx.t()
  def initialize_transfer(
        channel_id,
        from,
        to,
        amount
       ) do
    %ChannelOffchainTx{
      channel_id: channel_id,
      updates: [ChannelTransferUpdate.new(from, to, amount)],
      signatures: {<<>>, <<>>}
    }
  end

  #
  # Implementation of ChannelTransaction behaviour
  #

  @spec get_sequence(ChannelOffchainTx.t()) :: non_neg_integer()
  def get_sequence(%ChannelOffchainTx{sequence: sequence}) do
    sequence
  end

  @spec get_state_hash(ChannelOffchainTx.t()) :: binary()
  def get_state_hash(%ChannelOffchainTx{state_hash: state_hash}) do
    state_hash
  end

  @spec get_state_hash(ChannelOffchainTx.t()) :: Identifier.t()
  def get_channel_id(%ChannelOffchainTx{channel_id: channel_id}) do
    channel_id
  end

  @spec get_updates(ChannelOffchainTx.t()) :: list(ChannelUpdates.update_types())
  def get_updates(%ChannelOffchainTx{updates: updates}) do
    updates
  end

  # End of implementation of ChannelTransaction behaviour

  @doc """
  Encodes the offchain transaction to a form embedable in ChannelSoloCloseTx, ChannelSlashTx, ChannelSnapshotTx
  """
  @spec encode_to_payload(ChannelOffchainTx.t() | :empty) :: binary()
  def encode_to_payload(%ChannelOffchainTx{signatures: {sig1, sig2}} = state) do
    [
      :binary.encode_unsigned(@signed_tx_tag),
      :binary.encode_unsigned(@version),
      [sig1, sig2],
      Serialization.rlp_encode(state)
    ]
    |> ExRLP.encode
  end

  def encode_to_payload(:empty) do
    <<>>
  end

  @doc """
  Decodes the embedded payload of ChannelSoloCloseTx, ChannelSlashTx, ChannelSnapshotTx
  """
  @spec decode_from_payload(binary()) :: ChannelOffchainTx.t() | :empty | error()
  def decode_from_payload(<<>>) do
    {:ok, :empty}
  end

  def decode_from_payload([@signed_tx_tag, @version, [sig1, sig2], encoded_tx]) do
    decoded_tx = Serialization.rlp_decode_only(encoded_tx, ChannelOffchainTx)
    {:ok,
      %ChannelOffchainTx{decoded_tx | signatures: {sig1, sig2}}
    }
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

  #
  # Implementation of Serializable behaviour
  #

  @doc """
  Serializes the offchain transaction - signatures are not being included
  """
  @spec encode_to_list(ChannelOffchainTx.t()) :: list(binary())
  def encode_to_list(%ChannelOffchainTx{
    channel_id: %Identifier{type: :channel} = channel_id,
    sequence:   sequence,
    updates:    updates,
    state_hash: state_hash
  }) do
    encoded_updates = Enum.map(updates, &ChannelOffchainUpdate.to_list/1)
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(channel_id),
      :binary.encode_unsigned(sequence),
      encoded_updates,
      state_hash
    ]
  end

  @doc """
  Deserializes the serialzed offchain transaction. The resulting transaction does not contain any signatures.
  """
  @spec decode_from_list(non_neg_integer(), list(binary())) :: ChannelOffchainTx.t() | error()
  def decode_from_list(@version, [
        encoded_channel_id,
        sequence,
        encoded_updates,
        state_hash
      ]) do
    {:ok, channel_id} = Identifier.decode_from_binary(encoded_channel_id)
    %ChannelOffchainTx{
      channel_id: channel_id,
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

  # End of implementation of Serializable behaviour
end
