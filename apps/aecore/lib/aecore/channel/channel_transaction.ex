defmodule Aecore.Channel.ChannelTransaction do
  @doc """
    Behaviour specifying the necesary functions which any onchain/offchain transaction modifying the offchain chainstate must implement.
  """

  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Tx.SignedTx
  alias Aecore.ChannelOffchainTx

  @type channel_tx ::
          Aecore.Channel.ChannelOffchainTx
          | Aecore.Channel.Tx.ChannelCreateTx
          #| Aecore.Channel.Tx.ChannelWidhdrawTx
          #| Aecore.Channel.Tx.ChannelDepositTx

  def allowed_onchain_tx do
    [
      Aecore.Channel.Tx.ChannelCreateTx
      #Aecore.Channel.Tx.ChannelWidhdrawTx,
      #Aecore.Channel.Tx.ChannelDepositTx
    ]
  end

  @doc """
    Get the sequence number of the channel after applying the transaction to the offchain channel's state
  """
  @callback get_sequence(channel_tx()) :: non_neg_integer

  @doc """
    Get the state hash of the offchain chainstate after applying the transaction to the offchain channel's state
  """
  @callback get_state_hash(channel_tx()) :: binary()

  @doc """
    Get the id of the channel for which the transaction is ment to be applied
  """
  @callback get_channel_id(channel_tx()) :: Identifier.t()

  @doc """
    Get a list of offchain updates to the offchain chainstate
  """
  @callback get_updates(channel_tx()) :: list(ChannelOffchainUpdate.update_types())

  @spec is_signed_with?(SignedTx.t() | ChannelOffchainTx.t(), list(binary()) | binary()) :: boolean()
  def is_signed_with?(%SignedTx{data: %DataTx{type: type} = data} = tx, pubkey_list) when type in allowed_onchain_tx and is_list(pubkey_list) do
    senders = DataTx.senders(data)
    cond do
      lenght(senders) != lenght(pubkey_list) ->
        false
      Enum.reduce(senders, false, fn s, acc -> acc or s not in pubkey_list end) ->
        false
      true ->
        SignedTx.signatures_valid?(tx)
    end
  end

  def is_signed_with?(%SignedTx{data: %DataTx{type: type}} = tx, pubkey) when type in allowed_onchain_tx and is_binary(pubkey) do
    SignedTx.signature_valid_for?(tx, pubkey)
  end

  def is_signed_with?(%ChannelOffchainTx{} = tx, [initiator_pubkey, responder_pubkey]) do
    ChannelOffchainTx.validate(tx, {initiator_pubkey, responder_pubkey})
  end

  def is_signed_with?(%ChannelOffchainTx{} = tx, pubkey) when is_binary(pubkey) do
    ChannelOffchainTx.valid_initiator?(tx, pubkey) || ChannelOffchainTx.valid_responder?(tx, pubkey)
  end

  def is_signed_with?(_, _) do
    false
  end

  @spec add_signature(SignedTx.t() | ChannelOffchainTx.t(), binary(), binary()) :: {:ok, SignedTx.t() | ChannelOffchainTx.t()} | {:error, String.t()}
  def add_signature(%SignedTx{data: %DataTx{type: type}} = tx, pubkey, privkey) when type in allowed_onchain_tx do
    SignedTx.sign_tx(tx, pubkey, privkey)
  end

  def add_signature(%ChannelOffchainTx{} = tx, pubkey, privkey) when type in allowed_onchain_tx do
    ChannelOffchainTx.sign_with(tx, pubkey, privkey)
  end

  @spec unpack_tx(SignedTx.t() | ChannelOffchainTx.t()) :: channel_tx() | ChannelOffchainTx.t()
  defp unpack_tx(%SignedTx{data: %DataTx{type: type, payload: payload}}) when type in allowed_onchain_tx do
    payload
  end

  defp unpack_tx(%ChannelOffchainTx{} = tx) do
    tx
  end

  @spec sequence(SignedTx.t() | ChannelOffchainTx.t()) :: non_neg_integer()
  def sequence(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_sequence(structure)
  end

  @doc """
    Get the payload included in ChannelSoloCloseTx, ChannelSlashTx and ChannelSnapshotSoloTx
  """
  @spec dispute_payload(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def dispute_payload(%ChannelOffchainTx{} = tx) do
    ChannelOffchainTx.encode_to_payload(tx)
  end

  def dispute_payload(%SignedTx{data: %DataTx{type: type}}) when type in allowed_onchain_tx do
    <<>>
  end

  @doc """
    Specifies whether the effect of the transaction on the channel state is instant.
    If it's not then after receiving the Tx the channel is locked until the Tx was mined and min_depth confirmations were made
  """
  @spec is_instant?(SignedTx.t() | ChannelOffchainTx.t()) :: boolean()
  def is_instant?(%ChannelOffchainTx{} = tx) do
    true
  end

  def is_instant?(%SignedTx{data: %DataTx{type: type}}) when type in allowed_onchain_tx do
    false
  end

  @doc """
    Get the channel id for which the transaction is applied
  """
  @spec channel_id(SignedTx.t() | ChannelOffchainTx.t()) :: non_neg_integer()
  def channel_id(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_channel_id(structure)
  end

  @spec state_hash(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def state_hash(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_state_hash(structure)
  end

  @spec updates(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def updates(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_updates(structure)
  end
end
