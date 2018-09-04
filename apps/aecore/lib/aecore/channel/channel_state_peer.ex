defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Structure of Channel Peer State
  """

  alias Aecore.Channel.{
    ChannelOffchainTx,
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelCreateTx,
    ChannelTransaction,
    ChannelOffchainUpdate
  }

  alias Aecore.Channel.Worker, as: Channel

  alias Aecore.Channel.Tx.{
    ChannelCreateTx,
    ChannelCloseMutalTx,
    ChannelCloseSoloTx,
    ChannelSlashTx,
    ChannelSettleTx
  }

  alias Aecore.Keys.Wallet
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier
  alias Aecore.Account.Account
  alias Aecore.Poi.Poi

  @type fsm_state :: :initialized | :awaiting_full_tx | :awaiting_tx_confirmed | :open | :closing | :closed

  @type t :: %ChannelStatePeer{
          fsm_state: fsm_state(),
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          role: Channel.role(),
          channel_id: Identifier.t(),
          mutually_signed_tx: list(ChannelOffchainTx.t()),
          highest_half_signed_tx: ChannelOffChainTx.t() | nil,
          channel_reserve: non_neg_integer(),
          offchain_chainstate: Chainstate.t() | nil,
          sequence: non_neg_integer()
        }

  @type error :: {:error, binary()}

  defstruct [
    :fsm_state,
    :initiator_pubkey,
    :responder_pubkey,
    :role,
    :channel_id,
    :channel_reserve,
    mutually_signed_tx: [],
    highest_half_signed_tx: nil,
    offchain_chainstate: nil,
    sequence: 0
  ]

  require Logger

  use ExConstructor

  @spec channel_id(ChannelStatePeer.t()) :: Identifier.t()
  def channel_id(%ChannelStatePeer{channel_id: channel_id}), do: channel_id.value

  @spec verify_tx_and_apply(ChannelTransaction.channel_tx(), ChannelStatePeer.t(), list(Identifier.t()) | Identifier.t() ) :: {:ok, ChannelStatePeer.t()} | {:error, String.t()}
  defp verify_tx_and_apply(tx, %ChannelStatePeer{
    channel_id: channel_id,
    mutually_signed_tx: mutually_signed_tx,
    channel_reserve: channel_reserve,
    offchain_chainstate: offchain_chainstate,
    sequence: sequence
  } = peer, signed_with) do
    new_sequence = ChannelTransaction.get_sequence(tx)
    cond do
      #check if signed by the expected parties
      !ChannelTransaction.signed_with?(tx, signed_with) ->
        {:error, "#{__MODULE__}: Tx was not signed as expected"}
      #check channel id
      ChannelTransaction.get_channel_id(tx) !== channel_id ->
        {:error, "#{__MODULE__}: Wrong channel id in tx. Expected: #{inspect(channel_id)}, received: #{inspect(ChannelTransaction.get_channel_id(tx))}"}
      #check sequence
      new_sequence <= sequence ->
        {:error, "#{__MODULE__}: Invalid sequence in tx"}
      true ->
        #apply updates
        case ChannelOffchainUpdate.apply_updates(offchain_chainstate, ChannelTransaction.get_updates(tx), channel_reserve) do
          {:ok, new_offchain_chainstate} ->
            #update was succesfull - verify the state hash
            if(ChannelTransaction.get_state_hash(tx) !== Chainstate.calculate_root_hash(new_offchain_chainstate)) do
              {:error, "#{__MODULE__}: Wrong state hash in tx"}
            else
              {:ok, %ChannelStatePeer{
                peer |
                offchain_chainstate: new_offchain_chainstate,
                sequence: new_sequence,
                mutually_signed_tx: [tx | mutually_signed_tx]
              }}
            end
          {:error, _} = err ->
            err
        end
    end
  end

  @doc """
  Creates a channel from a list of mutually signed tx. The first tx in the list must be ChannelCreateTX. All the tx and updates are verified for corectness along the way.
  """
  @spec from_signed_tx_list(
          list(ChannelTransaction.channel_tx()),
          Channel.role()
        ) :: {:ok, ChannelStatePeer.t()} | {:error, String.t()}
  def from_signed_tx_list(offchain_tx_list, role) do

    offchain_tx_list_from_oldest = Enum.reverse(offchain_tx_list)

    [create_tx | _] = offchain_tx_list_from_oldest
    %SignedTx{data: %DataTx{
      type: ChannelCreateTx,
      payload: %ChannelCreateTx{
        initiator: initiator_pubkey,
        responder: responder_pubkey,
        channel_reserve: channel_reserve,
        channel_id: channel_id
      }}} = create_tx

    initial_state = %ChannelStatePeer{
            fsm_state: :open,
            initiator_pubkey: initiator_pubkey,
            responder_pubkey: responder_pubkey,
            role: role,
            channel_id: channel_id,
            channel_reserve: channel_reserve
          }

    Enum.reduce_while(offchain_tx_list_from_oldest, {:ok, initial_state},
      fn tx, {:ok, state} ->
        case verify_tx_and_apply(tx, state, [initiator_pubkey, responder_pubkey]) do
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
  @spec calculate_next_state_hash_for_new_tx(ChannelTransaction.channel_tx(), ChannelStatePeer.t()) :: {:ok, binary()} | {:error, String.t()}
  def calculate_next_state_hash_for_new_tx(tx, %ChannelStatePeer{
    channel_reserve: channel_reserve,
    offchain_chainstate: offchain_chainstate,
    sequence: sequence
  }) do
    if ChannelTransaction.get_sequence(tx) <= sequence do
      {:error, "#{__MODULE__}: Invalid sequence in tx"}
    else
      case ChannelOffchainUpdate.apply_updates(offchain_chainstate, ChannelTransaction.get_updates(tx), channel_reserve) do
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

  defp initialize_new_mutual_onchain_tx(%ChannelStatePeer{
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey},
    fee,
    nonce, type, spec) do
    DataTx.init(type, spec, [initiator_pubkey, responder_pubkey], fee, nonce)
  end

  defp validate_prepare_and_sign_new_channel_tx(
         %ChannelStatePeer{sequence: sequence} = peer_state, tx, priv_key) do
    tx1 = ChannelTransaction.set_sequence(tx, sequence+1)
    case calculate_next_state_hash_for_new_tx(tx1, peer_state) do
      {:ok, state_hash} ->
        tx1
        |> ChannelTransaction.set_state_hash(state_hash)
        |> ChannelTransaction.add_signature(priv_key)
      {:error, _} = err ->
        err
    end
  end

  defp half_signed_mutual_onchain_tx_from_spec(peer_state, fee, nonce, type, spec, priv_key) do
    data_tx = initialize_new_mutual_onchain_tx(peer_state, fee, nonce, type, spec)
    validate_prepare_and_sign_new_channel_tx(peer_state, data_tx, priv_key)
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
          Keys.privkey()
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
    raw_channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    channel_create_tx_spec = %{
          initiator: initiator_pubkey,
          initiator_amount: initiator_amount,
          responder: responder_pubkey,
          responder_amount: responder_amount,
          locktime: locktime,
          channel_reserve: channel_reserve,
          channel_id: raw_channel_id,
          state_hash: <<>>
        }
    case half_signed_mutual_onchain_tx_from_spec(peer_state, fee, nonce, ChannelCreateTx, channel_create_tx_spec, priv_key) do
      {:ok, half_signed_create_tx} ->
        {:ok,
          %ChannelStatePeer{
            peer_state |
            fsm_state: :awaiting_full_tx,
            mutually_signed_tx: [],
            highest_half_signed_tx: half_signed_create_tx,
            channel_id: Identifier.create_identity(raw_channel_id, :channel)
          },
          raw_channel_id,
          half_signed_create_tx}
      {:error, _} = err ->
        err
      end
  end

  def open(%ChannelStatePeer{}, _, _, _, _, _, _) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Signs provided open tx if it verifies. Can only be called in initialized state by responder. Returns altered ChannelPeerState, generated channel id and fully signed openTx.
  """
  @spec sign_open(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), SignedTx.t(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
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
        half_signed_create_tx,
        priv_key
      ) do
    data_tx = SignedTx.data_tx(half_signed_create_tx)
    nonce = DataTx.nonce(data_tx)

    %ChannelCreateTx{
      initiator_amount: tx_initiator_amount,
      responder_amount: tx_responder_amount,
      channel_reserve: tx_channel_reserve
    } = DataTx.payload(data_tx)

    raw_channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    cond do
      tx_initiator_amount != correct_initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initiator amount"}

      tx_responder_amount != correct_responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      tx_channel_reserve != correct_channel_reserve ->
        {:error, "#{__MODULE__}: Wrong channel reserve"}

      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "#{__MODULE__}: Wrong peers"}

      true ->
        #validate the state
        case recv_half_signed_tx(
          %ChannelStatePeer{peer_state | fsm_state: :open, channel_id: Identifier.create_identity(raw_channel_id, :channel)},
          half_signed_create_tx, priv_key
        ) do
          {:ok, new_peer_state, fully_signed_create_tx} ->
            {:ok, new_peer_state, raw_channel_id, fully_signed_create_tx}
          {:error, _} = err ->
            err
        end
    end
  end

  def sign_open(%ChannelStatePeer{}) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
    Receives a half signed transaction. Can only be called when the channel is fully open. If the transaction validates then returns a fully signed tx together with the altered state. If the received transaction is not instant then stores it and waits for min_depth confirmations.
  """
  def recv_half_signed_tx(%ChannelStatePeer{
    fsm_state: :open,
    mutually_signed_tx: mutually_signed_tx,
    highest_half_signed_tx: nil,
    } = peer_state, tx, privkey) do
    case verify_tx_and_apply(tx, peer_state, foreign_pubkey(peer_state)) do
      {:ok, new_peer_state} ->
        #The update validates on our side -> sign it and make a transition in the FSM
        case ChannelTransaction.add_signature(tx, privkey) do
          {:ok, fully_signed_tx} ->
            if ChannelTransaction.is_instant?(fully_signed_tx) do
              {:ok,
              %ChannelStatePeer{new_peer_state |
                #new peer state will contain the half signed tx so we are changing it to the correct tx
                mutually_signed_tx: [fully_signed_tx | mutually_signed_tx],
                fsm_state: :open,
                highest_half_signed_tx: nil
              },
              fully_signed_tx
            }
          else
            {:ok,
              %ChannelStatePeer{peer_state |
                fsm_state: :awaiting_tx_confirmed,
                highest_half_signed_tx: fully_signed_tx
              },
              fully_signed_tx
            }
          end
        {:error, _} = err ->
          err
        end
      {:error, _} = err ->
        err
    end
  end

  @doc """
    Receives a fully signed transaction. Can only be called when the peer awaits an incoming transaction. If the transaction is the awaited one and it fully validates then returns the altered state.
    If the received transaction is not instant then waits for min_depth confirmations.
  """
  def recv_fully_signed_tx(%ChannelStatePeer{
    fsm_state: :awaiting_full_tx,
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey,
    highest_half_signed_tx: last_signed} = peer_state, tx) do

    if(ChannelTransaction.get_state_hash(last_signed) !== ChannelTransaction.get_state_hash(tx)) do
      {:error, "#{__MODULE__} Received unexpected tx #{inspect(tx)}, expected: #{inspect(last_signed)}"}
    else
      case verify_tx_and_apply(tx, peer_state, [initiator_pubkey, responder_pubkey]) do
        {:ok, new_peer_state} ->
          if ChannelTransaction.is_instant?(tx) do
            {:ok,
              %ChannelStatePeer{new_peer_state |
                fsm_state: :open,
                highest_half_signed_tx: nil
              }
            }
          else
            {:ok,
              %ChannelStatePeer{peer_state |
                fsm_state: :awaiting_tx_confirmed,
                highest_half_signed_tx: tx
              }
            }
          end
        {:error, _} = err ->
          err
      end
    end
  end

  def recv_fully_signed_tx(%ChannelStatePeer{fsm_state: fsm_state}, _) do
    {:error, "Unexpected 'recv_fully_signed_tx' call. Current state is: #{fsm_state}"}
  end

  @doc """
   This is a callback for the future transaction watcher logic. This callback must be called when the last onchain TX from this channel has reached min_depth of confirmations. Verifies if the transaction was expected and applies it to the channel state.
  """
  def recv_confirmed_tx(%ChannelStatePeer{
    fsm_state: state,
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey,
    highest_half_signed_tx: awaiting_tx} = peer_state, tx) when state === :awaiting_full_tx or state === :awaiting_tx_confirmed do
    if(ChannelTransaction.get_state_hash(awaiting_tx) !== ChannelTransaction.get_state_hash(tx)) do
      {:error, "#{__MODULE__} Received unexpected tx #{inspect(tx)}, expected: #{inspect(awaiting_tx)}"}
    else
      case verify_tx_and_apply(tx, peer_state, [initiator_pubkey, responder_pubkey]) do
        {:ok, new_peer_state} ->
            {:ok,
              %ChannelStatePeer{new_peer_state |
                fsm_state: :open,
                highest_half_signed_tx: nil
              }
            }
        {:error, _} = err ->
          err
      end
    end
  end

  def recv_confirmed_tx(%ChannelStatePeer{}, _) do
    {:error, "Unexpected 'recv_confirmed_tx' call"}
  end

  @doc """
  Creates a transfer on channel. Can be called by both parties on open channel when there are no unconfirmed (half-signed) transfer. Returns altered ChannelStatePeer and the half signed tx.
  """
  @spec transfer(ChannelStatePeer.t(), non_neg_integer(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t()} | error()
  def transfer(
        %ChannelStatePeer{fsm_state: :open, channel_id: channel_id} =
          peer_state,
        amount,
        priv_key
      ) do
    unsigned_tx = ChannelOffchainTx.intialize_transfer(channel_id, our_pubkey(peer_state), foreign_pubkey(peer_state), amount)

    case validate_prepare_and_sign_new_channel_tx(peer_state, unsigned_tx, priv_key) do
      {:ok, half_signed_transfer_tx} ->
        {:ok,
          %ChannelStatePeer{
            peer_state |
            fsm_state: :awaiting_full_tx,
            highest_half_signed_tx: half_signed_transfer_tx
          },
          half_signed_transfer_tx
        }
      {:error, _} = err ->
        err
    end
  end

  def transfer(%ChannelStatePeer{} = state, _amount, _priv_key) do
    {:error, "#{__MODULE__}: Can't transfer now; channel state is #{state.fsm_state}"}
  end

  def our_offchain_account_balance(%ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}} = peer_state) do
    Account.balance(accounts, our_pubkey(peer_state))
  end

  def foreign_offchain_account_balance(%ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}} = peer_state) do
    Account.balance(accounts, foreign_pubkey(peer_state))
  end

  def calculate_state_hash(%ChannelStatePeer{offchain_chainstate: offchain_chainstate}) do
    Chainstate.calculate_state_hash(offchain_chainstate)
  end

  def most_recent_chainstate(%ChannelStatePeer{offchain_chainstate: offchain_chainstate}) do
    offchain_chainstate
  end

  def highest_sequence(%ChannelStatePeer{sequence: sequence}) do
    sequence
  end

  def dispute_poi_for_chainstate(%ChannelStatePeer{
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey},
    %Chainstate{} = offchain_chainstate) do
    Enum.reduce([initiator_pubkey, responder_pubkey], Poi.construct(offchain_chainstate),
      fn(pub_key, acc) ->
        {:ok, new_acc} = Poi.add_to_poi(:accounts, pub_key, offchain_chainstate, acc)
        new_acc
      end)
  end

  defp dispute_poi_for_latest_state(%ChannelStatePeer{} = peer_state) do
    dispute_poi_for_chainstate(peer_state, most_recent_chainstate(peer_state))
  end

  defp closing_balance_for(%ChannelStatePeer{offchain_chainstate: %Chainstate{accounts: accounts}}, pubkey) do
    #TODO: add the balance from associated contract accounts - not needed for 0.16
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
          channel_id: channel_id,
        } = peer_state,
        {fee_initiator, fee_responder},
        nonce,
        priv_key
      ) do
    initiator_amount = closing_balance_for(peer_state, initiator_pubkey)
    responder_amount = closing_balance_for(peer_state, responder_pubkey)
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
              channel_id: channel_id.value,
              initiator_amount: initiator_amount - fee_initiator,
              responder_amount: responder_amount - fee_responder
            },
            [initiator_pubkey, responder_pubkey],
            fee_initiator + fee_responder,
            nonce
          )

        {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, priv_key)
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

        {:ok, new_peer_state, close_signed_tx}
    end
  end

  def close(%ChannelStatePeer{} = state) do
    {:error, "#{__MODULE__}: Can't close now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Handles incoming channel close tx. If our highest state matches the incoming signs the tx and blocks any new transfers. Returns altered ChannelStatePeer and signed ChannelCloseMutalTx
  """
  @spec recv_close_tx(
          ChannelStatePeer.t(),
          SignedTx.t(),
          {non_neg_integer(), non_neg_integer()},
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def recv_close_tx(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          channel_id: channel_id,
        } = peer_state,
        half_signed_tx,
        {fee_initiator, fee_responder},
        priv_key
      ) do

    data_tx = SignedTx.data_tx(half_signed_tx)

    %ChannelCloseMutalTx{
      channel_id: tx_id,
      initiator_amount: tx_initiator_amount,
      responder_amount: tx_responder_amount
    } = DataTx.payload(data_tx)

    initiator_amount = closing_balance_for(peer_state, initiator_pubkey)
    responder_amount = closing_balance_for(peer_state, responder_pubkey)
    cond do
      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "#{__MODULE__}: Invalid senders"}

      tx_id != channel_id.value ->
        {:error, "#{__MODULE__}: Invalid id"}

      tx_initiator_amount != initiator_amount - fee_initiator ->
        {:error, "#{__MODULE__}: Invalid initiator_amount (check fee)"}

      tx_responder_amount != responder_amount - fee_responder ->
        {:error, "#{__MODULE__}: Invalid responder_amount (check fee)"}

      true ->
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

        {:ok, signed_close_tx} =
          SignedTx.sign_tx(half_signed_tx, priv_key)

        {:ok, new_peer_state, signed_close_tx}
    end
  end

  def recv_close_tx(%ChannelStatePeer{} = state, _, {_, _}, _) do
    {:error, "#{__MODULE__}: Can't receive close tx now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Changes channel state to closed. Should only be called when ChannelCloseMutalTx is mined.
  """
  def closed(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  @doc """
  Creates solo close tx for channel. Should only be called when no solo close tx-s were mined for this channel. Returns altered ChannelStatePeer and ChannelCloseSoloTx
  """
  @spec solo_close(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def solo_close(
        %ChannelStatePeer{mutually_signed_tx: [most_recent_tx | _]} = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data =
      DataTx.init(ChannelCloseSoloTx,
        %{
          channel_id: channel_id(peer_state),
          poi: dispute_poi_for_latest_state(peer_state),
          offchain_tx: ChannelTransaction.dispute_payload(most_recent_tx)
        },
        our_pubkey(peer_state), fee, nonce)

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, priv_key)
    {:ok, new_peer_state, our_slash_tx}
  end

  def slash(
        %ChannelStatePeer{mutually_signed_tx: [most_recent_tx | _]} = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data = DataTx.init(ChannelSlashTx,
      %{
        channel_id: channel_id(peer_state),
        poi: dispute_poi_for_latest_state(peer_state),
        offchain_tx: ChannelTransaction.dispute_payload(most_recent_tx)
      },
      our_pubkey(peer_state), fee, nonce)

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
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t() | nil} | error()
  def slashed(
        %ChannelStatePeer{
          mutually_signed_tx: [most_recent_tx | _]
        } = peer_state,
        slash_tx,
        fee,
        nonce,
        privkey
      ) do
    payload =
      slash_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()

    slash_hash =
      case payload do
        %ChannelCloseSoloTx{poi: poi} ->
          Poi.calculate_root_hash(poi)

        %ChannelSlashTx{poi: poi} ->
          Poi.calculate_root_hash(poi)
      end

    #We cannot relay on the sequence as SlashTx/SoloTx may not contain a payload.
    #Because SlashTx/SoloTx was mined the state hash present here must have been verified onchain
    #If it was verfied onchain then we needed to sign it - In conclusion we can relay on the state hash
    if slash_hash != ChannelTransaction.get_state_hash(most_recent_tx) do
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
  def settle(%ChannelStatePeer{fsm_state: :closing} = peer_state, fee, nonce, priv_key) do
    data =
      DataTx.init(
        ChannelSettleTx,
        %{channel_id: channel_id(peer_state)},
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
  @spec our_pubkey(ChannelStatePeer.t()) :: Wallet.pubkey()
  def our_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def our_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end

  @doc """
  Returns the pubkey of the other peer in channel.
  """
  @spec foreign_pubkey(ChannelStatePeer.t()) :: Wallet.pubkey()
  def foreign_pubkey(%ChannelStatePeer{role: :initiator, responder_pubkey: pubkey}) do
    pubkey
  end

  def foreign_pubkey(%ChannelStatePeer{role: :responder, initiator_pubkey: pubkey}) do
    pubkey
  end
end
