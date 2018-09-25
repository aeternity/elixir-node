defmodule Aecore.Channel.ChannelTransaction do
  @moduledoc """
    Behaviour specifying the necessary functions which any onchain/offchain transaction modifying the offchain chainstate must implement.
  """

  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Channel.ChannelOffChainTx

  @typedoc """
  Data structures capable of mutating the offchain chainstate off an state channel
  """
  @type channel_tx ::
          Aecore.Channel.ChannelOffChainTx
          | Aecore.Channel.Tx.ChannelCreateTx
          #| Aecore.Channel.Tx.ChannelWidhdrawTx
          #| Aecore.Channel.Tx.ChannelDepositTx

  @typedoc """
  Type of a signed channel transaction
  """
  @type signed_tx :: SignedTx.t() | ChannelOffChainTx.t()

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
  @callback offchain_updates(channel_tx()) :: list(ChannelOffChainUpdate.update_types())

  @doc """
  Preprocess checks for an incoming half signed transaction.
  This callback should check if the transaction is not malicious
  (for instance transfer updates should validate if the transfer is in the correct direction).
  """
  @spec half_signed_preprocess_check(signed_tx(), map()) :: :ok | error()
  def half_signed_preprocess_check(tx, opts) do
      tx
      |> offchain_updates
      |> do_half_signed_preprocess_check(opts)
  end

  @spec do_half_signed_preprocess_check(list(ChannelOffChainUpdate.update_types()), map()) :: :ok | error()
  defp do_half_signed_preprocess_check([update | rest], opts) do
    case ChannelOffChainUpdate.half_signed_preprocess_check(update, opts) do
      :ok ->
        do_half_signed_preprocess_check(rest, opts)
      {:error, _} = err ->
        err
    end
  end

  defp do_half_signed_preprocess_check([], _) do
    :ok
  end

  @doc """
  Verifies if the provided signed transaction was signed by the provided pubkey.
  Fails when the transaction was signed by more keys than expected.
  """
  @spec verify_half_signed_tx(signed_tx(), Keys.pubkey()) :: boolean()
  def verify_half_signed_tx(%SignedTx{data: %DataTx{type: type} = data_tx, signatures: signatures} = tx, pubkey) when type in @allowed_onchain_tx do
    senders = DataTx.senders(data_tx)

    length(senders) == 2 and pubkey in senders and length(signatures) == 1 and SignedTx.signature_valid_for?(tx, pubkey)
  end

  def verify_half_signed_tx(%ChannelOffChainTx{signatures: {_, <<>>}} = tx, pubkey) do
    ChannelOffChainTx.verify_signature_for_key(tx, pubkey)
  end

  def verify_half_signed_tx(%ChannelOffChainTx{}, _) do
    false
  end

  @doc """
  Verifies if the transaction was signed by both of the provided parties.
  """
  @spec verify_fully_signed_tx(signed_tx(), tuple()) :: boolean
  def verify_fully_signed_tx(%SignedTx{data: %DataTx{type: type} = data_tx} = tx, {pubkey1, pubkey2}) when type in @allowed_onchain_tx do
    senders = DataTx.senders(data_tx)

    length(senders) == 2 and pubkey1 in senders and pubkey2 in senders and SignedTx.signatures_valid?(tx, senders)
  end

  def verify_fully_signed_tx(%ChannelOffChainTx{} = tx, pubkeys) do
    ChannelOffChainTx.verify_signatures(tx, pubkeys)
  end

  @doc """
  Helper function for signing a channel transaction
  """
  @spec add_signature(signed_tx(), Keys.sign_priv_key()) :: {:ok, SignedTx.t() | ChannelOffChainTx.t()} | error()
  def add_signature(%SignedTx{data: %DataTx{type: type}} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%DataTx{type: type} = tx, privkey) when type in @allowed_onchain_tx do
    SignedTx.sign_tx(tx, privkey)
  end

  def add_signature(%ChannelOffChainTx{} = tx, privkey) do
    ChannelOffChainTx.sign(tx, privkey)
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

  def unsigned_payload(%ChannelOffChainTx{} = tx) do
    tx
  end

  @doc """
  Converts the transaction to a form suitable for initializing the payload in ChannelSoloCloseTx, ChannelSlashTx and ChannelSnapshotSoloTx
  """
  @spec dispute_payload(signed_tx()) :: ChannelOffChainTx.t() | :empty
  def dispute_payload(%ChannelOffChainTx{} = tx) do
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
  def requires_onchain_confirmation?(%ChannelOffChainTx{}) do
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

  def set_sequence(%ChannelOffChainTx{} = tx, sequence) do
    %ChannelOffChainTx{tx | sequence: sequence}
  end

  @doc """
  Sets the state hash of the offchain chainstate after the transaction is applied to the state channel
  """
  @spec set_state_hash(channel_tx(), binary()) :: channel_tx()
  def set_state_hash(%DataTx{type: type, payload: payload} = data_tx, state_hash) when type in @allowed_onchain_tx do
    #Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :state_hash, state_hash)}
  end

  def set_state_hash(%ChannelOffChainTx{} = tx, state_hash) do
    %ChannelOffChainTx{tx | state_hash: state_hash}
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
