defmodule Aecore.Channel.ChannelTransaction do
  @moduledoc """
    Behaviour specifying the necessary functions which any onchain/offchain transaction modifying the offchain chainstate must implement.
  """

  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Channel.ChannelOffchainTx

  @typedoc """
  Data structures capable of mutating the offchain chainstate off an state channel
  """
  @type channel_tx ::
          Aecore.Channel.ChannelOffchainTx
          | Aecore.Channel.Tx.ChannelCreateTx
          #| Aecore.Channel.Tx.ChannelWidhdrawTx
          #| Aecore.Channel.Tx.ChannelDepositTx

  @typedoc """
  Type of a signed channel transaction
  """
  @type signed_tx :: SignedTx.t() | ChannelOffchainTx.t()

  @allowed_onchain_tx [
      Aecore.Channel.Tx.ChannelCreateTx
      #Aecore.Channel.Tx.ChannelWidhdrawTx,
      #Aecore.Channel.Tx.ChannelDepositTx
    ]

  @typedoc """
  The type of errors returned by the functions in this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Get a list of offchain updates to the offchain chainstate
  """
  @callback offchain_updates(channel_tx()) :: list(ChannelOffchainUpdate.update_types())

  @doc """
  Helper for verifying signatures under a signed_tx() object.
  If the function received a list of public keys then fails if the transaction was signed parties not included in the list.
  If the function received a public key and the signature validates then the function succedes if the transaction was signed by other parties.
  """
  @spec verify_signatures_for_the_expected_parties(signed_tx(), list(Keys.pubkey()) | Keys.pubkey()) :: boolean()
  def verify_signatures_for_the_expected_parties(%SignedTx{data: %DataTx{type: type} = data} = tx, pubkey_list) when type in @allowed_onchain_tx and is_list(pubkey_list) do
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

  def verify_signatures_for_the_expected_parties(%SignedTx{data: %DataTx{type: type}} = tx, pubkey) when type in @allowed_onchain_tx and is_binary(pubkey) do
    SignedTx.signature_valid_for?(tx, pubkey)
  end

  def verify_signatures_for_the_expected_parties(%ChannelOffchainTx{} = tx, [initiator_pubkey, responder_pubkey]) do
    ChannelOffchainTx.verify_signatures(tx, {initiator_pubkey, responder_pubkey}) === :ok
  end

  def verify_signatures_for_the_expected_parties(%ChannelOffchainTx{} = tx, pubkey) when is_binary(pubkey) do
    ChannelOffchainTx.verify_signature_for_key(tx, pubkey)
  end

  def verify_signatures_for_the_expected_parties(_, _) do
    false
  end

  @doc """
  Helper function for signing a channel transaction
  """
  @spec add_signature(signed_tx(), Keys.sign_priv_key()) :: {:ok, SignedTx.t() | ChannelOffchainTx.t()} | error()
  def add_signature(%SignedTx{data: %DataTx{type: type}} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%DataTx{type: type} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%ChannelOffchainTx{} = tx, privkey) do
    ChannelOffchainTx.sign(tx, privkey)
  end

  @doc """
  Retrieves the unsigned payload from a signed/unsigned channel transaction
  """
  @spec unsigned_payload(signed_tx() | channel_tx()) :: channel_tx()
  def unsigned_payload(%SignedTx{} = signed_tx) do
    unsigned_payload(SignedTx.data_tx(signed_tx))
  end

  def unsigned_payload(%DataTx{type: type, payload: payload}) when type in @allowed_onchain_tx do
    payload
  end

  def unsigned_payload(%ChannelOffchainTx{} = tx) do
    tx
  end

  @doc """
  Converts the transaction to a form suitable for initializing the payload in ChannelSoloCloseTx, ChannelSlashTx and ChannelSnapshotSoloTx
  """
  @spec dispute_payload(signed_tx()) :: ChannelOffchainTx.t() | :empty
  def dispute_payload(%ChannelOffchainTx{} = tx) do
    tx
  end

  def dispute_payload(%SignedTx{data: %DataTx{type: type}}) when type in @allowed_onchain_tx do
    :empty
  end

  @doc """
  Specifies whether the effect of the transaction on the channel offchain state is instant.
  If it's not then after receiving the Tx the channel is locked until the Tx was mined and min_depth confirmations were made
  """
  @spec requires_onchain_confirmation?(signed_tx()) :: boolean()
  def requires_onchain_confirmation?(%ChannelOffchainTx{}) do
    false
  end

  def requires_onchain_confirmation?(%SignedTx{data: %DataTx{type: type}}) when type in @allowed_onchain_tx do
    true
  end

  @doc """
  Sets the sequence of the offchain state after applying the channel transaction to the state channel
  """
  @spec set_sequence(channel_tx(), non_neg_integer()) :: channel_tx()
  def set_sequence(%DataTx{type: type} = data_tx, _sequence) when type === Aecore.Channel.Tx.ChannelCreateTx do
    data_tx
  end

  def set_sequence(%DataTx{type: type, payload: payload} = data_tx, sequence) when type in @allowed_onchain_tx and type !== Aecore.Channel.Tx.ChannelCreateTx do
    #Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :sequence, sequence)}
  end

  def set_sequence(%ChannelOffchainTx{} = tx, sequence) do
    %ChannelOffchainTx{tx | sequence: sequence}
  end

  @doc """
  Sets the state hash of the offchain chainstate after the transaction is applied to the state channel
  """
  @spec set_state_hash(channel_tx(), binary()) :: channel_tx()
  def set_state_hash(%DataTx{type: type, payload: payload} = data_tx, state_hash) when type in @allowed_onchain_tx do
    #Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :state_hash, state_hash)}
  end

  def set_state_hash(%ChannelOffchainTx{} = tx, state_hash) do
    %ChannelOffchainTx{tx | state_hash: state_hash}
  end

  @doc """
  Get a list of updates to the offchain chainstate
  """
  @spec offchain_updates(signed_tx()) :: list(ChannelOffchainUpdate.update_types())
  def offchain_updates(tx) do
    structure = unsigned_payload(tx)
    structure.__struct__.offchain_updates(structure)
  end
end
