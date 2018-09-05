defmodule Aecore.Channel.ChannelOffchainTx do
  @moduledoc """
  Structure of OffChain Channel Transaction
  """

  alias Aecore.Channel.ChannelOffchainTx
  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Keys
  alias Aeutil.Serialization
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
          non_neg_integer()
        ) :: ChannelOffchainTx.t()
  def create(channel_id, sequence) do
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
        state_hash: state_hash,
        signatures: signatures
      }) do
    %ChannelOffchainTx{
      channel_id: channel_id,
      sequence: sequence,
      state_hash: state_hash,
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
  Checks if there is a signature for the specified pubkey
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

  @doc """
  Signs an offchain Tx.
  """
  @spec sign_with(ChannelOffchainTx.t(), Keys.sign_priv_key()) ::
          ChannelOffchainTx.t()
  def sign_with(%ChannelOffchainTx{signatures: {<<>>, <<>>}} = state, priv_key) do
    sig =
      state
      |> Serialization.rlp_encode()
      |> Keys.sign(priv_key)

    {:ok, %ChannelOffchainTx{state | signatures: {sig, <<>>}}}
  end

  def sign_with(%ChannelOffchainTx{signatures: {sig1, <<>>}} = state, priv_key) do
    sig2 =
      state
      |> Serialization.rlp_encode()
      |> Keys.sign(priv_key)

    if sig2 > sig1 do
      {:ok, %ChannelOffchainTx{state | signatures: {sig1, sig2}}}
    else
      {:ok, %ChannelOffchainTx{state | signatures: {sig2, sig1}}}
    end
  end

  def intialize_transfer(
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

  def get_sequence(%ChannelOffchainTx{sequence: sequence}) do
    sequence
  end

  def get_state_hash(%ChannelOffchainTx{state_hash: state_hash}) do
    state_hash
  end

  def get_channel_id(%ChannelOffchainTx{channel_id: channel_id}) do
    channel_id
  end

  def get_updates(%ChannelOffchainTx{updates: updates}) do
    updates
  end

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

  def decode_from_payload(<<>>) do
    :empty
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
