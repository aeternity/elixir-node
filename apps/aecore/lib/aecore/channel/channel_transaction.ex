defmodule Aecore.Channel.ChannelTransaction do
  @moduledoc """
    Behaviour specifying the necesary functions which any onchain/offchain transaction modifying the offchain chainstate must implement.
  """

  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Channel.ChannelOffchainTx

  @type channel_tx ::
          Aecore.Channel.ChannelOffchainTx
          | Aecore.Channel.Tx.ChannelCreateTx
          #| Aecore.Channel.Tx.ChannelWidhdrawTx
          #| Aecore.Channel.Tx.ChannelDepositTx

  @allowed_onchain_tx [
      Aecore.Channel.Tx.ChannelCreateTx
      #Aecore.Channel.Tx.ChannelWidhdrawTx,
      #Aecore.Channel.Tx.ChannelDepositTx
    ]

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

  @spec signed_with?(SignedTx.t() | ChannelOffchainTx.t(), list(binary()) | binary()) :: boolean()
  def signed_with?(%SignedTx{data: %DataTx{type: type} = data} = tx, pubkey_list) when type in @allowed_onchain_tx and is_list(pubkey_list) do
    #Check if the TX was send by the expected parties
    senders = DataTx.senders(data)
    cond do
      length(senders) != length(pubkey_list) ->
        false
      Enum.reduce(senders, false, fn s, acc -> acc or s not in pubkey_list end) ->
        false
      true ->
        #Make sure that the signatures are valid
        SignedTx.signatures_valid?(tx)
    end
  end

  def signed_with?(%SignedTx{data: %DataTx{type: type}} = tx, pubkey) when type in @allowed_onchain_tx and is_binary(pubkey) do
    SignedTx.signature_valid_for?(tx, pubkey)
  end

  def signed_with?(%ChannelOffchainTx{} = tx, [initiator_pubkey, responder_pubkey]) do
    ChannelOffchainTx.validate(tx, {initiator_pubkey, responder_pubkey}) === :ok
  end

  def signed_with?(%ChannelOffchainTx{} = tx, pubkey) when is_binary(pubkey) do
    ChannelOffchainTx.signature_valid_for?(tx, pubkey)
  end

  def signed_with?(_, _) do
    false
  end

  @spec add_signature(SignedTx.t() | ChannelOffchainTx.t(), binary()) :: {:ok, SignedTx.t() | ChannelOffchainTx.t()} | {:error, String.t()}
  def add_signature(%SignedTx{data: %DataTx{type: type}} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%DataTx{type: type} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%ChannelOffchainTx{} = tx, privkey) do
    ChannelOffchainTx.sign_with(tx, privkey)
  end

  @spec unpack_tx(SignedTx.t() | ChannelOffchainTx.t()) :: channel_tx() | ChannelOffchainTx.t()
  defp unpack_tx(%SignedTx{} = signed_tx) do
    unpack_tx(SignedTx.data_tx(signed_tx))
  end

  defp unpack_tx(%DataTx{type: type, payload: payload}) when type in @allowed_onchain_tx do
    payload
  end

  defp unpack_tx(%ChannelOffchainTx{} = tx) do
    tx
  end

  @doc """
    Get the payload included in ChannelSoloCloseTx, ChannelSlashTx and ChannelSnapshotSoloTx
  """
  @spec dispute_payload(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def dispute_payload(%ChannelOffchainTx{} = tx) do
    tx
  end

  def dispute_payload(%SignedTx{data: %DataTx{type: type}}) when type in @allowed_onchain_tx do
    :empty
  end

  @doc """
    Specifies whether the effect of the transaction on the channel state is instant.
    If it's not then after receiving the Tx the channel is locked until the Tx was mined and min_depth confirmations were made
  """
  @spec is_instant?(SignedTx.t() | ChannelOffchainTx.t()) :: boolean()
  def is_instant?(%ChannelOffchainTx{}) do
    true
  end

  def is_instant?(%SignedTx{data: %DataTx{type: type}}) when type in @allowed_onchain_tx do
    false
  end

  @spec get_sequence(SignedTx.t() | ChannelOffchainTx.t()) :: non_neg_integer()
  def get_sequence(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_sequence(structure)
  end

  def set_sequence(%DataTx{type: type, payload: payload} = data_tx, sequence) when type in @allowed_onchain_tx do
    #Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :sequence, sequence)}
  end

  def set_sequence(%ChannelOffchainTx{} = tx, sequence) do
    %ChannelOffchainTx{tx | sequence: sequence}
  end

  @doc """
    Get the channel id for which the transaction is applied
  """
  @spec get_channel_id(SignedTx.t() | ChannelOffchainTx.t()) :: non_neg_integer()
  def get_channel_id(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_channel_id(structure)
  end

  @spec get_state_hash(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def get_state_hash(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_state_hash(structure)
  end

  def set_state_hash(%DataTx{type: type, payload: payload} = data_tx, state_hash) when type in @allowed_onchain_tx do
    #Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :state_hash, state_hash)}
  end

  def set_state_hash(%ChannelOffchainTx{} = tx, state_hash) do
    %ChannelOffchainTx{tx | state_hash: state_hash}
  end

  @spec get_updates(SignedTx.t() | ChannelOffchainTx.t()) :: binary()
  def get_updates(tx) do
    structure = unpack_tx(tx)
    structure.__struct__.get_updates(structure)
  end
end
