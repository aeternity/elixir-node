defmodule Aecore.Channel.ChannelOffChainTx do
  @moduledoc """
  Structure of an Offchain Channel Transaction. Implements a cryptographically signed container for channel updates associated with an offchain chainstate.
  """

  @behaviour Aecore.Channel.ChannelTransaction

  alias Aecore.Channel.ChannelOffChainTx
  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Keys
  alias Aecore.Chain.Identifier

  @version 1
  # TypeToTag.type_to_tag(Aecore.Tx.SignedTx)
  @signed_tx_tag 11

  @typedoc """
  Structure of the ChannelOffChainTx type
  """
  @type t :: %ChannelOffChainTx{
          channel_id: binary(),
          sequence: non_neg_integer(),
          updates: list(ChannelOffChainUpdate.update_types()),
          state_hash: binary(),
          signatures: {binary(), binary()}
        }

  @typedoc """
  The type of errors returned by the functions in this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of Aecore ChannelOffChainTx structure

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

  use Aecore.Util.Serializable

  require Logger

  @doc """
  Validates the signatures under the offchain transaction.
  """
  @spec verify_signatures(ChannelOffChainTx.t(), {Keys.pubkey(), Keys.pubkey()}) :: :ok | error()
  def verify_signatures(%ChannelOffChainTx{signatures: {_, _}} = state, {
        initiator_pubkey,
        responder_pubkey
      }) do
    cond do
      !verify_signature_for_key(state, initiator_pubkey) ->
        {:error, "#{__MODULE__}: Invalid initiator signature"}

      !verify_signature_for_key(state, responder_pubkey) ->
        {:error, "#{__MODULE__}: Invalid responder signature"}

      true ->
        :ok
    end
  end

  def verify_signatures(%ChannelOffChainTx{}, _) do
    {:error, "#{__MODULE__}: Invalid signatures count"}
  end

  @doc """
  Checks if there is a signature for the specified pubkey.
  """
  @spec verify_signature_for_key(ChannelOffChainTx.t(), Keys.pubkey()) :: boolean()
  def verify_signature_for_key(%ChannelOffChainTx{signatures: {<<>>, _}}, _) do
    false
  end

  def verify_signature_for_key(
        %ChannelOffChainTx{signatures: {sig1, sig2}} = state,
        pubkey
      ) do
    binary_form = rlp_encode(state)

    Keys.verify(binary_form, sig1, pubkey) or
      verify_signature_for_key(%ChannelOffChainTx{state | signatures: {sig2, <<>>}}, pubkey)
  end

  @spec signature_for_offchain_tx(ChannelOffChainTx.t(), Keys.sign_priv_key()) :: binary()
  defp signature_for_offchain_tx(%ChannelOffChainTx{} = offchain_tx, priv_key)
       when is_binary(priv_key) do
    offchain_tx
    |> rlp_encode()
    |> Keys.sign(priv_key)
  end

  @doc """
  Signs the offchain transaction with the provided private key.
  """
  @spec sign(ChannelOffChainTx.t(), Keys.sign_priv_key()) :: ChannelOffChainTx.t()
  def sign(%ChannelOffChainTx{signatures: {<<>>, <<>>}} = offchain_tx, priv_key) do
    sig = signature_for_offchain_tx(offchain_tx, priv_key)

    {:ok, %ChannelOffChainTx{offchain_tx | signatures: {sig, <<>>}}}
  end

  def sign(%ChannelOffChainTx{signatures: {sig1, <<>>}} = offchain_tx, priv_key) do
    sig2 = signature_for_offchain_tx(offchain_tx, priv_key)

    if sig2 > sig1 do
      {:ok, %ChannelOffChainTx{offchain_tx | signatures: {sig1, sig2}}}
    else
      {:ok, %ChannelOffChainTx{offchain_tx | signatures: {sig2, sig1}}}
    end
  end

  @doc """
  Creates a new offchain transaction containing a transfer update between the specified accounts. The resulting offchain transaction is not tied to any offchain chainstate.
  """
  @spec initialize_transfer(binary(), Keys.pubkey(), Keys.pubkey(), non_neg_integer()) ::
          ChannelOffChainTx.t()
  def initialize_transfer(channel_id, from, to, amount) do
    %ChannelOffChainTx{
      channel_id: channel_id,
      updates: [ChannelTransferUpdate.new(from, to, amount)],
      signatures: {<<>>, <<>>}
    }
  end

  @spec offchain_updates(ChannelOffChainTx.t()) :: list(ChannelUpdates.update_types())
  def offchain_updates(%ChannelOffChainTx{updates: updates}) do
    updates
  end

  @doc """
  Encodes the offchain transaction to a form embeddable in ChannelSoloCloseTx, ChannelSlashTx, ChannelSnapshotTx
  """
  @spec encode_to_payload(ChannelOffChainTx.t() | :empty) :: binary()
  def encode_to_payload(%ChannelOffChainTx{signatures: {sig1, sig2}} = state) do
    [
      :binary.encode_unsigned(@signed_tx_tag),
      :binary.encode_unsigned(@version),
      [sig1, sig2],
      rlp_encode(state)
    ]
    |> ExRLP.encode()
  end

  def encode_to_payload(:empty) do
    <<>>
  end

  @doc """
  Decodes the embedded payload of ChannelSoloCloseTx, ChannelSlashTx, ChannelSnapshotTx
  """
  @spec decode_from_payload(binary()) :: {:ok, ChannelOffChainTx.t()} | :empty | error()
  def decode_from_payload(<<>>) do
    {:ok, :empty}
  end

  def decode_from_payload([@signed_tx_tag, @version, [sig1, sig2], encoded_tx]) do
    case rlp_decode(encoded_tx) do
      {:ok, %ChannelOffChainTx{} = decoded_tx} ->
        {:ok, %ChannelOffChainTx{decoded_tx | signatures: {sig1, sig2}}}

      {:error, _} = err ->
        err
    end
  end

  def decode_from_payload([@signed_tx_tag, @version | invalid_data]) do
    {:error,
     "#{__MODULE__}: decode_from_payload: Invalid serialization - #{inspect(invalid_data)}"}
  end

  def decode_from_payload([@signed_tx_tag, version | _]) do
    {:error, "#{__MODULE__}: decode_from_payload: Unknown version #{version}"}
  end

  def decode_from_payload([tag | _]) do
    {:error, "#{__MODULE__}: decode_from_payload: Invalid payload tag #{tag}"}
  end

  @doc """
  Serializes the offchain transaction - signatures are not being included
  """
  @spec encode_to_list(ChannelOffChainTx.t()) :: list(binary())
  def encode_to_list(%ChannelOffChainTx{
        channel_id: channel_id,
        sequence: sequence,
        updates: updates,
        state_hash: state_hash
      }) do
    encoded_updates = Enum.map(updates, &ChannelOffChainUpdate.encode_to_list/1)

    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(channel_id, :channel),
      :binary.encode_unsigned(sequence),
      encoded_updates,
      state_hash
    ]
  end

  @doc """
  Deserializes the serialized offchain transaction. The resulting transaction does not contain any signatures.
  """
  @spec decode_from_list(non_neg_integer(), list(binary())) :: ChannelOffChainTx.t() | error()
  def decode_from_list(@version, [
        encoded_channel_id,
        sequence,
        encoded_updates,
        state_hash
      ]) do
    with {:ok, channel_id} <-
           Identifier.decode_from_binary_to_value(encoded_channel_id, :channel),
         decoded_updates <- Enum.map(encoded_updates, &ChannelOffChainUpdate.decode_from_list/1),
         # Look for errors
         errors <- for({:error, _} = err <- decoded_updates, do: err),
         nil <- List.first(errors) do
      %ChannelOffChainTx{
        channel_id: channel_id,
        sequence: :binary.decode_unsigned(sequence),
        updates: decoded_updates,
        state_hash: state_hash
      }
    else
      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
