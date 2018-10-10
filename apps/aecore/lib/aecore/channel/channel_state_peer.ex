defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Module defining the structure of the Channel Peer State
  """

  alias Aecore.Channel.{
    ChannelOffChainTx,
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelCreateTx,
    ChannelTransaction,
    ChannelOffChainUpdate
  }

  alias Aecore.Channel.Worker, as: Channel

  alias Aecore.Channel.Tx.{
    ChannelCreateTx,
    ChannelCloseMutalTx,
    ChannelCloseSoloTx,
    ChannelSlashTx,
    ChannelSettleTx
  }

  alias Aecore.Keys
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Account.Account
  alias Aecore.Poi.Poi

  @type fsm_state ::
          :initialized | :awaiting_full_tx | :awaiting_tx_confirmed | :open | :closing | :closed

  @typedoc "Structure of the ChannelStatePeer Transaction type"
  @type t :: %ChannelStatePeer{
          fsm_state: fsm_state(),
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          role: Channel.role(),
          channel_id: binary(),
          mutually_signed_tx: list(ChannelOffChainTx.t()),
          highest_half_signed_tx: ChannelOffChainTx.t() | nil,
          channel_reserve: non_neg_integer(),
          offchain_chainstate: Chainstate.t() | nil
        }

  @typedoc "Reason for the error"
  @type error :: {:error, String.t()}

  defstruct [
    :fsm_state,
    :initiator_pubkey,
    :responder_pubkey,
    :role,
    :channel_id,
    :channel_reserve,
    mutually_signed_tx: [],
    highest_half_signed_tx: nil,
    offchain_chainstate: nil
  ]

  require Logger

  @spec process_fully_signed_tx(ChannelTransaction.signed_tx(), ChannelStatePeer.t()) ::
          {:ok, ChannelStatePeer.t()} | error()
  defp process_fully_signed_tx(
         tx,
         %ChannelStatePeer{initiator_pubkey: initiator_pubkey, responder_pubkey: responder_pubkey} =
           peer_state
       ) do
    if ChannelTransaction.verify_fully_signed_tx(tx, {initiator_pubkey, responder_pubkey}) do
      process_tx(tx, peer_state)
    else
      {:error, "#{__MODULE__}: Transaction was not signed by both parties"}
    end
  end

  @spec process_half_signed_tx(ChannelTransaction.signed_tx(), ChannelStatePeer.t()) ::
          {:ok, ChannelStatePeer.t()} | error()
  defp process_half_signed_tx(tx, %ChannelStatePeer{} = peer_state) do
    if ChannelTransaction.verify_half_signed_tx(tx, foreign_pubkey(peer_state)) do
      process_tx(tx, peer_state)
    else
      {:error, "#{__MODULE__}: Transaction was not signed by the foreign party"}
    end
  end

  @spec process_tx(ChannelTransaction.signed_tx(), ChannelStatePeer.t()) ::
          {:ok, ChannelStatePeer.t()} | error()
  defp process_tx(tx, %ChannelStatePeer{} = peer_state) do
    with :ok <- validate_tx(tx, peer_state),
         {:ok, updated_offchain_chainstate} <- update_offchain_chainstate(tx, peer_state) do
      {:ok,
       %ChannelStatePeer{
         peer_state
         | offchain_chainstate: updated_offchain_chainstate
       }}
    else
      {:error, _} = err ->
        err
    end
  end

  @spec validate_tx(
          ChannelTransaction.signed_tx() | ChannelTransaction.channel_tx(),
          ChannelStatePeer.t()
        ) :: :ok | error()
  defp validate_tx(
         tx,
         %ChannelStatePeer{
           channel_id: channel_id
         } = peer_state
       ) do
    cur_sequence = ChannelStatePeer.sequence(peer_state)

    tx_channel_id = ChannelTransaction.channel_id(tx)
    tx_sequence = ChannelTransaction.sequence(tx)

    cond do
      tx_channel_id !== channel_id ->
        {:error,
         "#{__MODULE__}: Wrong channel id in tx. Expected: #{inspect(channel_id)}, received: #{
           inspect(tx_channel_id)
         }"}

      # check sequence
      tx_sequence <= cur_sequence ->
        {:error,
         "#{__MODULE__}: Old sequence. Expected bigger then #{cur_sequence}, got #{tx_sequence}"}

      true ->
        :ok
    end
  end

  @spec update_offchain_chainstate(ChannelTransaction.signed_tx(), ChannelStatePeer.t()) ::
          {:ok, Chainstate.t()} | error()
  defp update_offchain_chainstate(tx, %ChannelStatePeer{
         channel_reserve: channel_reserve,
         offchain_chainstate: offchain_chainstate
       }) do
    unsigned_tx = ChannelTransaction.unsigned_payload(tx)
    state_hash = unsigned_tx.state_hash

    with {:ok, updated_offchain_chainstate} <-
           ChannelOffChainUpdate.apply_updates(
             offchain_chainstate,
             ChannelTransaction.offchain_updates(tx),
             channel_reserve
           ),
         ^state_hash <- Chainstate.calculate_root_hash(updated_offchain_chainstate) do
      {:ok, updated_offchain_chainstate}
    else
      {:error, _} = err ->
        err

      hash when is_binary(hash) ->
        {:error,
         "#{__MODULE__}: Wrong state hash in tx, expected #{inspect(hash)}, got: #{
           inspect(state_hash)
         }"}
    end
  end

  @doc """
  Creates a channel from a list of mutually signed tx. The first tx in the list must be ChannelCreateTX. All the tx and updates are verified for corectness along the way.
  """
  @spec from_signed_tx_list(
          list(ChannelTransaction.signed_tx()),
          Channel.role()
        ) :: {:ok, ChannelStatePeer.t()} | error()
  def from_signed_tx_list(offchain_tx_list, role) do
    offchain_tx_list_from_oldest = Enum.reverse(offchain_tx_list)

    [create_tx | _] = offchain_tx_list_from_oldest

    %SignedTx{
      data:
        %DataTx{
          type: ChannelCreateTx,
          payload: %ChannelCreateTx{
            channel_reserve: channel_reserve
          },
          senders: [
            %Identifier{value: initiator_pubkey},
            %Identifier{value: responder_pubkey}
          ]
        } = data_tx
    } = create_tx

    channel_id = ChannelStateOnChain.id(data_tx)

    initial_state = %ChannelStatePeer{
      fsm_state: :open,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      channel_id: channel_id,
      channel_reserve: channel_reserve
    }

    Enum.reduce_while(offchain_tx_list_from_oldest, {:ok, initial_state}, fn tx, {:ok, state} ->
      case process_fully_signed_tx(tx, state) do
        {:ok, _} = new_acc ->
          {:cont, new_acc}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  @doc """
  Creates channel from open transaction assuming no transactions in channel.
  """
  @spec from_open(SignedTx.t(), Channel.role()) :: ChannelStatePeer.t()
  def from_open(open_tx, role) do
    from_signed_tx_list([open_tx], role)
  end

  @doc """
    Gets a list of mutually signed transactions for importing the channel.
  """
  @spec get_signed_tx_list(ChannelStatePeer.t()) :: list(ChannelTransaction.channel_tx())
  def get_signed_tx_list(%ChannelStatePeer{mutually_signed_tx: mutually_signed_tx}) do
    mutually_signed_tx
  end

  @doc """
    Calculates the state hash of the offchain chainstate after aplying the transaction.
    Only basic verification is done.
  """
  @spec calculate_next_state_hash_for_new_tx(
          ChannelTransaction.channel_tx(),
          ChannelStatePeer.t()
        ) :: {:ok, binary()} | error()
  def calculate_next_state_hash_for_new_tx(
        tx,
        %ChannelStatePeer{
          channel_reserve: channel_reserve,
          offchain_chainstate: offchain_chainstate
        } = peer_state
      ) do
    if ChannelTransaction.sequence(tx) <= ChannelStatePeer.sequence(peer_state) do
      {:error, "#{__MODULE__}: Invalid sequence in tx"}
    else
      case ChannelOffChainUpdate.apply_updates(
             offchain_chainstate,
             ChannelTransaction.offchain_updates(tx),
             channel_reserve
           ) do
        {:ok, new_offchain_chainstate} ->
          {:ok, Chainstate.calculate_root_hash(new_offchain_chainstate)}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Creates initialized channel.
  """
  @spec initialize(
          binary(),
          Wallet.pubkey(),
          Wallet.pubkey(),
          non_neg_integer(),
          Channel.role()
        ) :: ChannelStatePeer.t()
  def initialize(
        temporary_id,
        initiator_pubkey,
        responder_pubkey,
        channel_reserve,
        role
      ) do
    %ChannelStatePeer{
      fsm_state: :initialized,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      channel_reserve: channel_reserve,
      channel_id: temporary_id
    }
  end

  # @spec initialize_new_mutual_onchain_tx(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), module(), ChannelCreateTx.payload() | ChannelWidhdrawTx.payload() | ChannelDepositTx.payload()) :: DataTx.t()
  @spec initialize_new_mutual_onchain_tx(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          module(),
          ChannelCreateTx.payload()
        ) :: DataTx.t()
  defp initialize_new_mutual_onchain_tx(
         %ChannelStatePeer{
           initiator_pubkey: initiator_pubkey,
           responder_pubkey: responder_pubkey
         },
         fee,
         nonce,
         type,
         spec
       ) do
    DataTx.init(type, spec, [initiator_pubkey, responder_pubkey], fee, nonce)
  end

  # Verifies that the contents of the raw unsigned transaction are valid by simulating a potential update.
  # If the transaction is valid(properly updates the offchain chainstate) then irreversibly ties the transaction to the updated chainstate and sings it.
  @spec validate_prepare_and_sign_new_channel_tx(
          ChannelStatePeer.t(),
          ChannelTransaction.channel_tx(),
          Keys.sign_priv_key()
        ) :: ChannelTransaction.signed_tx()
  defp validate_prepare_and_sign_new_channel_tx(
         %ChannelStatePeer{} = peer_state,
         raw_unsigned_tx,
         priv_key
       ) do
    cur_sequence = ChannelStatePeer.sequence(peer_state)
    unvalidated_unsigned_tx = ChannelTransaction.set_sequence(raw_unsigned_tx, cur_sequence + 1)

    case calculate_next_state_hash_for_new_tx(unvalidated_unsigned_tx, peer_state) do
      {:ok, state_hash} ->
        # validation was successfull
        unvalidated_unsigned_tx
        # ties the tx to the updated state
        |> ChannelTransaction.set_state_hash(state_hash)
        # signs the prepared tx
        |> ChannelTransaction.add_signature(priv_key)

      {:error, _} = err ->
        err
    end
  end

  @spec half_signed_mutual_onchain_tx_from_spec(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          module(),
          map(),
          Keys.sign_priv_key()
        ) :: ChannelTransaction.signed_tx()
  defp half_signed_mutual_onchain_tx_from_spec(peer_state, fee, nonce, type, spec, priv_key) do
    data_tx = initialize_new_mutual_onchain_tx(peer_state, fee, nonce, type, spec)
    validate_prepare_and_sign_new_channel_tx(peer_state, data_tx, priv_key)
  end

  @spec channel_fsm_transition_on_validated_signed_tx(
          ChannelStatePeer.t(),
          ChannelTransaction.signed_tx(),
          :confirmed | :half_signed | ChannelStatePeer.t()
        ) :: ChannelStatePeer.t()
  defp channel_fsm_transition_on_validated_signed_tx(
         %ChannelStatePeer{mutually_signed_tx: mutually_signed_tx} = updated_peer_state,
         validated_trusted_tx,
         %ChannelStatePeer{} = prev_peer_state
       ) do
    if ChannelTransaction.requires_onchain_confirmation?(validated_trusted_tx) do
      %ChannelStatePeer{
        prev_peer_state
        | fsm_state: :awaiting_tx_confirmed,
          highest_half_signed_tx: validated_trusted_tx
      }
    else
      %ChannelStatePeer{
        updated_peer_state
        | fsm_state: :open,
          highest_half_signed_tx: nil,
          mutually_signed_tx: [validated_trusted_tx | mutually_signed_tx]
      }
    end
  end

  defp channel_fsm_transition_on_validated_signed_tx(
         %ChannelStatePeer{mutually_signed_tx: mutually_signed_tx} = updated_peer_state,
         validated_trusted_tx,
         :confirmed
       ) do
    %ChannelStatePeer{
      updated_peer_state
      | fsm_state: :open,
        highest_half_signed_tx: nil,
        mutually_signed_tx: [validated_trusted_tx | mutually_signed_tx]
    }
  end

  defp channel_fsm_transition_on_validated_signed_tx(
         %ChannelStatePeer{} = updated_peer_state,
         validated_trusted_tx,
         :half_signed
       ) do
    %ChannelStatePeer{
      updated_peer_state
      | fsm_state: :awaiting_full_tx,
        highest_half_signed_tx: validated_trusted_tx
    }
  end

  @doc """
  Creates channel open tx. Can only be called in initialized state by initiator. Changes fsm state to half_signed. Specified fee, nonce, initiator_amount and responder_amount are for the created tx. Returns altered ChannelPeerState, generated channel id, half signed open tx.
  """
  @spec open(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :initiator,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          mutually_signed_tx: [],
          highest_half_signed_tx: nil,
          channel_reserve: channel_reserve
        } = peer_state,
        initiator_amount,
        responder_amount,
        locktime,
        fee,
        nonce,
        priv_key
      ) do
    channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    channel_create_tx_spec = %{
      initiator: initiator_pubkey,
      initiator_amount: initiator_amount,
      responder: responder_pubkey,
      responder_amount: responder_amount,
      locktime: locktime,
      channel_reserve: channel_reserve,
      channel_id: channel_id,
      state_hash: <<>>
    }

    case half_signed_mutual_onchain_tx_from_spec(
           peer_state,
           fee,
           nonce,
           ChannelCreateTx,
           channel_create_tx_spec,
           priv_key
         ) do
      {:ok, half_signed_create_tx} ->
        {:ok,
         %ChannelStatePeer{
           peer_state
           | channel_id: channel_id
         }
         |> channel_fsm_transition_on_validated_signed_tx(half_signed_create_tx, :half_signed),
         channel_id, half_signed_create_tx}

      {:error, _} = err ->
        err
    end
  end

  def open(%ChannelStatePeer{}, _, _, _, _, _, _) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Signs provided open tx if it verifies. Can only be called in initialized state by the responder. Returns an altered ChannelPeerState, generated channel id and fully signed open tx.
  """
  @spec sign_open(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          SignedTx.t(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def sign_open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :responder,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          mutually_signed_tx: [],
          highest_half_signed_tx: nil,
          channel_reserve: correct_channel_reserve
        } = peer_state,
        correct_initiator_amount,
        correct_responder_amount,
        correct_locktime,
        %SignedTx{data: %DataTx{type: ChannelCreateTx, nonce: nonce}} = half_signed_create_tx,
        priv_key
      ) do
    channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    case receive_half_signed_tx(
           %ChannelStatePeer{peer_state | fsm_state: :open, channel_id: channel_id},
           half_signed_create_tx,
           priv_key,
           %{
             initiator_amount: correct_initiator_amount,
             responder_amount: correct_responder_amount,
             channel_reserve: correct_channel_reserve,
             locktime: correct_locktime
           }
         ) do
      {:ok, new_peer_state, fully_signed_create_tx} ->
        {:ok, new_peer_state, channel_id, fully_signed_create_tx}

      {:error, _} = err ->
        err
    end
  end

  def sign_open(%ChannelStatePeer{}, _, _, _, _, _) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Receives a half signed transaction. Can only be called when the channel is fully open. If the transaction validates then returns a fully signed tx together with the altered state.
  Can receive an optional map for preprocess checks - by default the initiating/responding peer is passed to the update verification stack.
  If the received transaction requires onchain confirmation then stores it and waits for min_depth confirmations.
  """
  @spec receive_half_signed_tx(
          ChannelStatePeer.t(),
          ChannelTransaction.signed_tx(),
          Keys.sign_priv_key(),
          map()
        ) :: {:ok, ChannelStatePeer.t(), ChannelTransaction.signed_tx()} | error()
  def receive_half_signed_tx(
        %ChannelStatePeer{fsm_state: :open} = peer_state,
        tx,
        privkey,
        opts \\ %{}
      ) do
    with :ok <-
           ChannelTransaction.half_signed_preprocess_check(
             tx,
             Map.merge(opts, %{
               our_pubkey: our_pubkey(peer_state),
               foreign_pubkey: foreign_pubkey(peer_state)
             })
           ),
         {:ok, new_peer_state} <- process_half_signed_tx(tx, peer_state),
         # The update validates on our side -> sign it
         {:ok, fully_signed_tx} <- ChannelTransaction.add_signature(tx, privkey) do
      # And make a transition in the FSM
      {:ok,
       channel_fsm_transition_on_validated_signed_tx(new_peer_state, fully_signed_tx, peer_state),
       fully_signed_tx}
    else
      {:error, _} = err ->
        err
    end
  end

  @doc """
  Receives a fully signed transaction. Can only be called when the peer awaits an incoming transaction. If the transaction is the awaited one and it fully validates then returns the altered state.
  If the received transaction requires onchain confirmation then waits for min_depth confirmations.
  """
  @spec receive_fully_signed_tx(ChannelStatePeer.t(), ChannelTransaction.signed_tx()) ::
          {:ok, ChannelStatePeer.t()} | error()
  def receive_fully_signed_tx(
        %ChannelStatePeer{
          fsm_state: :awaiting_full_tx,
          highest_half_signed_tx: last_signed
        } = peer_state,
        tx
      ) do
    if ChannelTransaction.unsigned_payload(last_signed).state_hash ==
         ChannelTransaction.unsigned_payload(tx).state_hash do
      case process_fully_signed_tx(tx, peer_state) do
        {:ok, new_peer_state} ->
          {:ok, channel_fsm_transition_on_validated_signed_tx(new_peer_state, tx, peer_state)}

        {:error, _} = err ->
          err
      end
    else
      {:error,
       "#{__MODULE__} Received unexpected tx #{inspect(tx)}, expected: #{inspect(last_signed)}"}
    end
  end

  def receive_fully_signed_tx(%ChannelStatePeer{fsm_state: fsm_state}, _) do
    {:error, "Unexpected 'receive_fully_signed_tx' call. Current state is: #{fsm_state}"}
  end

  @doc """
  This is a callback for the future transaction watcher logic. This callback must be called when the last onchain TX from this channel has reached min_depth of confirmations. Verifies if the transaction was expected and applies it to the channel state.
  """
  @spec receive_confirmed_tx(ChannelStatePeer.t(), ChannelTransaction.signed_tx()) ::
          {:ok, ChannelStatePeer.t()} | error()
  def receive_confirmed_tx(
        %ChannelStatePeer{
          fsm_state: state,
          highest_half_signed_tx: awaiting_tx
        } = peer_state,
        tx
      )
      when state == :awaiting_full_tx or state == :awaiting_tx_confirmed do
    if ChannelTransaction.unsigned_payload(awaiting_tx) ===
         ChannelTransaction.unsigned_payload(tx) do
      case process_fully_signed_tx(tx, peer_state) do
        {:ok, new_peer_state} ->
          {:ok, channel_fsm_transition_on_validated_signed_tx(new_peer_state, tx, :confirmed)}

        {:error, _} = err ->
          err
      end
    else
      {:error,
       "#{__MODULE__} Received unexpected tx #{inspect(tx)}, expected: #{inspect(awaiting_tx)}"}
    end
  end

  def receive_confirmed_tx(%ChannelStatePeer{} = peer_state, tx) do
    {:error,
     "Unexpected 'receive_confirmed_tx' call. Peer state is #{inspect(peer_state)}. Received confimation on #{
       inspect(tx)
     }"}
  end

  @doc """
  Creates a transfer on channel. Can be called by both parties on open channel when there are no unconfirmed (half-signed) transfer. Returns altered ChannelStatePeer and the half signed tx.
  """
  @spec transfer(ChannelStatePeer.t(), non_neg_integer(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t()} | error()
  def transfer(
        %ChannelStatePeer{fsm_state: :open, channel_id: channel_id} = peer_state,
        amount,
        priv_key
      ) do
    unsigned_tx =
      ChannelOffChainTx.initialize_transfer(
        channel_id,
        our_pubkey(peer_state),
        foreign_pubkey(peer_state),
        amount
      )

    case validate_prepare_and_sign_new_channel_tx(peer_state, unsigned_tx, priv_key) do
      {:ok, half_signed_transfer_tx} ->
        {:ok,
         channel_fsm_transition_on_validated_signed_tx(
           peer_state,
           half_signed_transfer_tx,
           :half_signed
         ), half_signed_transfer_tx}

      {:error, _} = err ->
        err
    end
  end

  def transfer(%ChannelStatePeer{fsm_state: fsm_state}, _amount, _priv_key) do
    {:error, "#{__MODULE__}: Can't transfer now; channel state is #{fsm_state}"}
  end

  @doc """
  Retrieves our offchain account balance from the latest offchain chainstate
  """
  @spec our_offchain_account_balance(ChannelStatePeer.t()) :: non_neg_integer()
  def our_offchain_account_balance(
        %ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}} = peer_state
      ) do
    Account.balance(accounts, our_pubkey(peer_state))
  end

  @doc """
  Retrieves the foreign offchain account balance from the latest offchain chainstate
  """
  @spec foreign_offchain_account_balance(ChannelStatePeer.t()) :: non_neg_integer()
  def foreign_offchain_account_balance(
        %ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}} = peer_state
      ) do
    Account.balance(accounts, foreign_pubkey(peer_state))
  end

  @doc """
  Calculates the state hash of the most recent offchain chainstate
  """
  @spec calculate_state_hash(ChannelStatePeer.t()) :: binary()
  def calculate_state_hash(%ChannelStatePeer{offchain_chainstate: offchain_chainstate}) do
    Chainstate.calculate_root_hash(offchain_chainstate)
  end

  @doc """
  Retrieves the most recent offchain chainstate
  """
  @spec most_recent_chainstate(ChannelStatePeer.t()) :: Chainstate.t()
  def most_recent_chainstate(%ChannelStatePeer{offchain_chainstate: offchain_chainstate}) do
    offchain_chainstate
  end

  @doc """
  Retrieves the sequence of the current round of updates
  """
  @spec sequence(ChannelStatePeer.t()) :: non_neg_integer()
  def sequence(%ChannelStatePeer{mutually_signed_tx: [last_tx | _]}) do
    ChannelTransaction.sequence(last_tx)
  end

  def sequence(%ChannelStatePeer{}) do
    # The initial sequence is 0. ChannelCreateTx SHOULD have sequence 1 but MUST have sequence larger than 0.
    0
  end

  @doc """
  Creates a Poi for disputes from the given chainstate
  """
  @spec dispute_poi_for_chainstate(ChannelStatePeer.t(), Chainstate.t()) :: Poi.t()
  def dispute_poi_for_chainstate(
        %ChannelStatePeer{initiator_pubkey: initiator_pubkey, responder_pubkey: responder_pubkey},
        %Chainstate{} = offchain_chainstate
      ) do
    Enum.reduce(
      [initiator_pubkey, responder_pubkey],
      Poi.construct(offchain_chainstate),
      fn pub_key, acc ->
        {:ok, new_acc} = Poi.add_to_poi(:accounts, pub_key, offchain_chainstate, acc)
        new_acc
      end
    )
  end

  @spec dispute_poi_for_latest_state(ChannelStatePeer.t()) :: Poi.t()
  defp dispute_poi_for_latest_state(%ChannelStatePeer{} = peer_state) do
    dispute_poi_for_chainstate(peer_state, most_recent_chainstate(peer_state))
  end

  @spec final_channel_balance_for(ChannelStatePeer.t(), Keys.pubkey()) :: non_neg_integer()
  defp final_channel_balance_for(
         %ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}},
         pubkey
       ) do
    # In future versions we need to add the balance from associated contract accounts - not needed for 0.16
    Account.balance(accounts, pubkey)
  end

  @doc """
  Creates mutal close tx for open channel. This blocks any new transfers on channel. Returns: altered ChannelStatePeer and ChannelCloseMutalTx
  """
  @spec close(
          ChannelStatePeer.t(),
          {non_neg_integer(), non_neg_integer()},
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def close(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          channel_id: channel_id
        } = peer_state,
        {fee_initiator, fee_responder},
        nonce,
        priv_key
      ) do
    initiator_amount = final_channel_balance_for(peer_state, initiator_pubkey)
    responder_amount = final_channel_balance_for(peer_state, responder_pubkey)

    cond do
      fee_initiator > initiator_amount ->
        {:error, "#{__MODULE__}: Initiator fee bigger then initiator balance"}

      fee_responder > responder_amount ->
        {:error, "#{__MODULE__}: Responder fee bigger then responder balance"}

      true ->
        close_tx =
          DataTx.init(
            ChannelCloseMutalTx,
            %{
              channel_id: channel_id,
              initiator_amount: initiator_amount - fee_initiator,
              responder_amount: responder_amount - fee_responder
            },
            [],
            fee_initiator + fee_responder,
            nonce
          )

        {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, priv_key)
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

        {:ok, new_peer_state, close_signed_tx}
    end
  end

  def close(%ChannelStatePeer{fsm_state: fsm_state}) do
    {:error, "#{__MODULE__}: Can't close now; channel state is #{fsm_state}"}
  end

  @doc """
  Handles incoming channel close tx. If our highest state matches the incoming signs the tx and blocks any new transfers. Returns altered ChannelStatePeer and signed ChannelCloseMutalTx
  """
  @spec receive_close_tx(
          ChannelStatePeer.t(),
          SignedTx.t(),
          {non_neg_integer(), non_neg_integer()},
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def receive_close_tx(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          channel_id: channel_id
        } = peer_state,
        %SignedTx{
          data: %DataTx{
            payload: %ChannelCloseMutalTx{
              channel_id: tx_id,
              initiator_amount: tx_initiator_amount,
              responder_amount: tx_responder_amount
            }
          }
        } = half_signed_tx,
        {fee_initiator, fee_responder},
        priv_key
      ) do
    initiator_amount = final_channel_balance_for(peer_state, initiator_pubkey)
    responder_amount = final_channel_balance_for(peer_state, responder_pubkey)

    cond do
      tx_id != channel_id ->
        {:error, "#{__MODULE__}: Invalid id"}

      tx_initiator_amount != initiator_amount - fee_initiator ->
        {:error, "#{__MODULE__}: Invalid initiator_amount (check fee)"}

      tx_responder_amount != responder_amount - fee_responder ->
        {:error, "#{__MODULE__}: Invalid responder_amount (check fee)"}

      true ->
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

        {:ok, signed_close_tx} = SignedTx.sign_tx(half_signed_tx, priv_key)

        {:ok, new_peer_state, signed_close_tx}
    end
  end

  def receive_close_tx(%ChannelStatePeer{} = state, _, {_, _}, _) do
    {:error, "#{__MODULE__}: Can't receive close tx now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Changes the channel state to closed. Should only be called when a ChannelCloseMutalTx is mined.
  """
  @spec closed(ChannelStatePeer.t()) :: ChannelStatePeer.t()
  def closed(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  @doc """
  Creates solo close tx for channel. Should only be called when no solo close tx-s were mined for this channel. Returns altered ChannelStatePeer and ChannelCloseSoloTx
  """
  @spec solo_close(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def solo_close(
        %ChannelStatePeer{channel_id: channel_id, mutually_signed_tx: [most_recent_tx | _]} =
          peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data =
      DataTx.init(
        ChannelCloseSoloTx,
        %{
          channel_id: channel_id,
          poi: dispute_poi_for_latest_state(peer_state),
          offchain_tx: ChannelTransaction.dispute_payload(most_recent_tx)
        },
        our_pubkey(peer_state),
        fee,
        nonce
      )

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, priv_key)
    {:ok, new_peer_state, our_slash_tx}
  end

  @doc """
  Creates a slash transaction from the most recent offchain chainstate.
  """
  @spec slash(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), SignedTx.t()}
  def slash(
        %ChannelStatePeer{channel_id: channel_id, mutually_signed_tx: [most_recent_tx | _]} =
          peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data =
      DataTx.init(
        ChannelSlashTx,
        %{
          channel_id: channel_id,
          poi: dispute_poi_for_latest_state(peer_state),
          offchain_tx: ChannelTransaction.dispute_payload(most_recent_tx)
        },
        our_pubkey(peer_state),
        fee,
        nonce
      )

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, priv_key)
    {:ok, new_peer_state, our_slash_tx}
  end

  @doc """
  Handles mined ChnanelSlashTx and ChannelCloseSoloTx. Provided fee and nonce are for potentially created SlashTx. Pubkey and Privkey don't have to match any of channel parties. Returns altered ChannelPeerState and ChannelSlashTx if we have higher signed state.
  """
  @spec slashed(
          ChannelStatePeer.t(),
          SignedTx.t(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t() | nil} | error()
  def slashed(
        %ChannelStatePeer{
          mutually_signed_tx: [most_recent_tx | _]
        } = peer_state,
        %SignedTx{
          data: %DataTx{
            payload: payload
          }
        },
        fee,
        nonce,
        privkey
      ) do
    slash_hash =
      case payload do
        %ChannelCloseSoloTx{poi: poi} ->
          Poi.calculate_root_hash(poi)

        %ChannelSlashTx{poi: poi} ->
          Poi.calculate_root_hash(poi)
      end

    # We cannot rely on the sequence as SlashTx/SoloTx may not contain a payload.
    # Because SlashTx/SoloTx was mined the state hash present here must have been verified onchain
    # If it was verfied onchain then we needed to sign it - In conclusion we can rely on the state hash
    if slash_hash != ChannelTransaction.unsigned_payload(most_recent_tx).state_hash do
      slash(peer_state, fee, nonce, privkey)
    else
      new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
      {:ok, new_peer_state, nil}
    end
  end

  @doc """
  Creates channel settle tx.
  """
  @spec settle(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, SignedTx.t()} | error()
  def settle(
        %ChannelStatePeer{
          channel_id: channel_id,
          fsm_state: :closing,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey
        } = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    initiator_amount = final_channel_balance_for(peer_state, initiator_pubkey)
    responder_amount = final_channel_balance_for(peer_state, responder_pubkey)

    data =
      DataTx.init(
        ChannelSettleTx,
        %{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        our_pubkey(peer_state),
        fee,
        nonce
      )

    SignedTx.sign_tx(data, priv_key)
  end

  @doc """
  Changes channel state to closed. Should only be called when ChannelSettleTx is mined.
  """
  @spec settled(ChannelStatePeer.t()) :: ChannelStatePeer.t()
  def settled(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  @doc """
  Returns our pubkey from in channel.
  """
  @spec our_pubkey(ChannelStatePeer.t()) :: Keys.pubkey()
  def our_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def our_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end

  @doc """
  Returns the pubkey of the other peer in channel.
  """
  @spec foreign_pubkey(ChannelStatePeer.t()) :: Keys.pubkey()
  def foreign_pubkey(%ChannelStatePeer{role: :initiator, responder_pubkey: pubkey}) do
    pubkey
  end

  def foreign_pubkey(%ChannelStatePeer{role: :responder, initiator_pubkey: pubkey}) do
    pubkey
  end
end
