defmodule Aecore.Channel.ChannelTransaction do
  @moduledoc """
    Behaviour specifying the necessary functions which any onchain/offchain transaction modifying the offchain chainstate must implement.
  """

  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Channel.ChannelOffChainTx
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Chain.Identifier

  @typedoc """
  Data structures capable of mutating the offchain chainstate off an state channel
  """
  @type channel_tx ::
          ChannelOffChainTx
          | ChannelCreateTx
  # | Aecore.Channel.Tx.ChannelWidhdrawTx
  # | Aecore.Channel.Tx.ChannelDepositTx

  @typedoc """
  Type of a signed channel transaction
  """
  @type signed_tx :: SignedTx.t() | ChannelOffChainTx.t()

  @typedoc """
  Types of allowed OnChain transactions
  """
  # | ChannelWidhdrawTx | ChannelDepositTx
  @type onchain_tx :: ChannelCreateTx

  @typedoc """
  Payloads of allowed OnChain transactions
  """
  # | ChannelWidhdrawTx.payload() | ChannelDepositTx.payload()
  @type onchain_tx_payload :: ChannelCreateTx.payload()

  @allowed_onchain_tx [
    ChannelCreateTx
    # Aecore.Channel.Tx.ChannelWidhdrawTx,
    # Aecore.Channel.Tx.ChannelDepositTx
  ]

  @typedoc """
  The type of errors returned by the functions in this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Get a list of offchain updates to the offchain chainstate
  """
  @callback offchain_updates(signed_tx() | DataTx.t()) ::
              list(ChannelOffChainUpdate.update_types())

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

  @spec do_half_signed_preprocess_check(list(ChannelOffChainUpdate.update_types()), map()) ::
          :ok | error()
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
  def verify_half_signed_tx(
        %SignedTx{
          data: %DataTx{
            type: type,
            senders: [%Identifier{value: initiator}, %Identifier{value: responder}]
          },
          signatures: signatures
        } = tx,
        pubkey
      )
      when type in @allowed_onchain_tx do
    (pubkey == initiator or pubkey == responder) and length(signatures) == 1 and
      SignedTx.signature_valid_for?(tx, pubkey)
  end

  def verify_half_signed_tx(%SignedTx{}, _) do
    false
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
  def verify_fully_signed_tx(
        %SignedTx{
          data: %DataTx{
            type: type,
            senders: [%Identifier{value: initiator}, %Identifier{value: responder}]
          }
        } = tx,
        {correct_initiator, correct_responder}
      )
      when type in @allowed_onchain_tx do
    initiator == correct_initiator and responder == correct_responder and
      SignedTx.signatures_valid?(tx, [initiator, responder])
  end

  def verify_fully_signed_tx(%ChannelOffChainTx{} = tx, pubkeys) do
    ChannelOffChainTx.verify_signatures(tx, pubkeys)
  end

  @doc """
  Helper function for signing a channel transaction
  """
  @spec add_signature(signed_tx(), Keys.sign_priv_key()) ::
          {:ok, SignedTx.t() | ChannelOffChainTx.t()} | error()
  def add_signature(%SignedTx{data: %DataTx{type: type}} = tx, privkey)
      when type in @allowed_onchain_tx do
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
  def unsigned_payload(%SignedTx{data: data_tx}) do
    unsigned_payload(data_tx)
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

  def requires_onchain_confirmation?(%SignedTx{data: %DataTx{type: type}})
      when type in @allowed_onchain_tx do
    true
  end

  @doc """
  Sequence of the state after applying the transaction to the chainstate.
  """
  @spec sequence(signed_tx() | DataTx.t()) :: non_neg_integer()
  def sequence(%SignedTx{data: data_tx}) do
    sequence(data_tx)
  end

  def sequence(%DataTx{type: ChannelCreateTx}) do
    1
  end

  def sequence(tx) do
    unsigned_payload(tx).sequence
  end

  @doc """
  Channel id for which the transaction is designated.
  """
  @spec channel_id(signed_tx() | DataTx.t()) :: binary()
  def channel_id(%SignedTx{data: data_tx}) do
    channel_id(data_tx)
  end

  def channel_id(%DataTx{type: ChannelCreateTx} = data_tx) do
    ChannelStateOnChain.id(data_tx)
  end

  def channel_id(tx) do
    unsigned_payload(tx).channel_id
  end

  @doc """
  Sets the sequence of the offchain state after applying the channel transaction to the state channel
  """
  @spec set_sequence(channel_tx(), non_neg_integer()) :: channel_tx()
  def set_sequence(%DataTx{type: type} = data_tx, _sequence)
      when type === Aecore.Channel.Tx.ChannelCreateTx do
    data_tx
  end

  def set_sequence(%DataTx{type: type, payload: payload} = data_tx, sequence)
      when type in @allowed_onchain_tx and type !== Aecore.Channel.Tx.ChannelCreateTx do
    # Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :sequence, sequence)}
  end

  def set_sequence(%ChannelOffChainTx{} = tx, sequence) do
    %ChannelOffChainTx{tx | sequence: sequence}
  end

  @doc """
  Sets the state hash of the offchain chainstate after the transaction is applied to the state channel
  """
  @spec set_state_hash(channel_tx(), binary()) :: channel_tx()
  def set_state_hash(%DataTx{type: type, payload: payload} = data_tx, state_hash)
      when type in @allowed_onchain_tx do
    # Maybe consider doing proper dispatching here?
    %DataTx{data_tx | payload: Map.put(payload, :state_hash, state_hash)}
  end

  def set_state_hash(%ChannelOffChainTx{} = tx, state_hash) do
    %ChannelOffChainTx{tx | state_hash: state_hash}
  end

  @doc """
  Get a list of updates to the offchain chainstate
  """
  @spec offchain_updates(signed_tx() | DataTx.t()) :: list(ChannelOffchainUpdate.update_types())
  def offchain_updates(tx) do
    structure = unsigned_payload(tx)
    structure.__struct__.offchain_updates(tx)
  end
end
