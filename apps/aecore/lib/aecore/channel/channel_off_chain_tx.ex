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
  alias Aecore.Tx.SignedTx
  alias Aeutil.TypeToTag

  @version 1
  @signedtx_version 1

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
        %ChannelOffChainTx{signatures: {signature1, signature2}} = state,
        pubkey
      ) do
    Keys.verify(signing_form(state), signature1, pubkey) or
      verify_signature_for_key(%ChannelOffChainTx{state | signatures: {signature2, <<>>}}, pubkey)
  end

  @spec signature_for_offchain_tx(ChannelOffChainTx.t(), Keys.sign_priv_key()) :: binary()
  defp signature_for_offchain_tx(%ChannelOffChainTx{} = offchain_tx, priv_key)
       when is_binary(priv_key) do
    offchain_tx
    |> signing_form()
    |> Keys.sign(priv_key)
  end

  defp signing_form(%ChannelOffChainTx{} = tx) do
    rlp_encode(%ChannelOffChainTx{tx | signatures: {<<>>, <<>>}})
  end

  @doc """
  Signs the offchain transaction with the provided private key.
  """
  @spec sign(ChannelOffChainTx.t(), Keys.sign_priv_key()) :: ChannelOffChainTx.t()
  def sign(%ChannelOffChainTx{signatures: {<<>>, <<>>}} = offchain_tx, priv_key) do
    signature = signature_for_offchain_tx(offchain_tx, priv_key)

    {:ok, %ChannelOffChainTx{offchain_tx | signatures: {signature, <<>>}}}
  end

  def sign(%ChannelOffChainTx{signatures: {existing_signature, <<>>}} = offchain_tx, priv_key) do
    new_signature = signature_for_offchain_tx(offchain_tx, priv_key)

    if new_signature > existing_signature do
      {:ok, %ChannelOffChainTx{offchain_tx | signatures: {existing_signature, new_signature}}}
    else
      {:ok, %ChannelOffChainTx{offchain_tx | signatures: {new_signature, existing_signature}}}
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
  Serializes the offchain transaction - signatures are not being included
  """
  @spec encode_to_list(ChannelOffChainTx.t()) :: list(binary())
  def encode_to_list(%ChannelOffChainTx{
        signatures: {<<>>, <<>>},
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

  def encode_to_list(%ChannelOffChainTx{
        signatures: {_, _}
      }) do
    throw("#{__MODULE__}: Serialization.rlp_encode is not supported for offchaintx")
  end

  def rlp_encode(%ChannelOffChainTx{signatures: {<<>>, <<>>}} = tx) do
    Serialization.rlp_encode(tx)
  end

  def rlp_encode(%ChannelOffChainTx{signatures: {signature1, signature2}} = tx) do
    {:ok, signedtx_tag} = TypeToTag.type_to_tag(SignedTx)

    ExRLP.encode([
      signedtx_tag,
      @signedtx_version,
      [signature1, signature2],
      ChannelOffChainTx.rlp_encode(%ChannelOffChainTx{tx | signatures: {<<>>, <<>>}})
    ])
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
      {:ok,
       %ChannelOffChainTx{
         channel_id: channel_id,
         sequence: :binary.decode_unsigned(sequence),
         updates: decoded_updates,
         state_hash: state_hash
       }}
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

  def rlp_decode_signed(binary) do
    result =
      try do
        ExRLP.decode(binary)
      rescue
        e ->
          {:error, "#{__MODULE__}: rlp_decode: IIllegal serialization: #{Exception.message(e)}"}
      end

    {:ok, signedtx_tag} = TypeToTag.type_to_tag(SignedTx)
    signedtx_tag_bin = :binary.encode_unsigned(signedtx_tag)
    signedtx_ver_bin = :binary.encode_unsigned(@signedtx_version)

    case result do
      [^signedtx_tag_bin, ^signedtx_ver_bin, [signature1, signature2], data]
      when signature1 < signature2 ->
        case rlp_decode(data) do
          {:ok, %ChannelOffChainTx{} = tx} ->
            {:ok, %ChannelOffChainTx{tx | signatures: {signature1, signature2}}}

          {:error, _} = error ->
            error
        end

      [^signedtx_tag_bin, ^signedtx_ver_bin | _] ->
        {:error, "#{__MODULE__}: Invalid signedtx serialization"}

      [^signedtx_tag_bin | _] ->
        {:error, "#{__MODULE__}: Unknown signedtx version"}

      list when is_list(list) ->
        {:error, "#{__MODULE__}: Invalid tag"}

      {:error, _} = error ->
        error
    end
  end
end
