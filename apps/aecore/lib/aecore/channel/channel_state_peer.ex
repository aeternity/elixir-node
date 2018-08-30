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
  alias Aecore.Account.AccountStateTree

  @type fsm_state :: :initialized | :awaiting_full_tx | :awaiting_tx_confirmed | :open | :closing | :closed

  @type t :: %ChannelStatePeer{
          fsm_state: fsm_state(),
          initiator_pubkey: Wallet.pubkey(),
          responder_pubkey: Wallet.pubkey(),
          role: Channel.role(),
          channel_id: Identifier.t(),
          mutualy_signed_tx: list(ChannelOffchainTx.t()),
          highest_half_signed_tx: ChannelOffChainTx.t() | nil,
          minimal_deposit: non_neg_integer(),
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
    :minimal_deposit,
    mutually_signed_tx: [],
    highest_half_signed_tx: nil,
    offchain_chainstate: nil,
    sequence: 0
  ]

  require Logger

  use ExConstructor

  @spec id(ChannelStatePeer.t()) :: Identifier.t()
  def id(%ChannelStatePeer{channel_id: channel_id}), do: channel_id

  @spec verify_and_apply_on_chainstate(ChannelTransaction.channel_tx(), ChannelStatePeer.t(), list(Identifier.t()) | Identifier.t() ) :: {:ok, ChannelStatePeer.t()} | {:error, String.t()}
  defp verify_tx_and_apply(tx, %ChannelStatePeer{
    channel_id: channel_id,
    mutually_signed_tx: mutually_signed_tx,
    minimal_deposit: minimal_deposit,
    offchain_chainstate: offchain_chainstate,
    sequence: sequence
  } = peer, signed_with) do
    new_sequence = ChannelTransaction.sequence(tx)
    cond do
      #check if signed by the expected parties
      !ChannelTransaction.is_signed_with(tx, signed_with) ->
        {:error, "#{__MODULE__}: Tx was not signed as expected"}
      #check channel id
      ChannelTransaction.channel_id(tx) !== channel_id ->
        {:error, "#{__MODULE__}: Wrong channel id in tx"}
      #check sequence
      new_sequence <= sequence ->
        {:error, "#{__MODULE__}: Invalid sequence in tx"}
      true ->
        #apply updates
        case ChannelOffchainUpdate.apply_updates(offchain_chainstate, ChannelTransaction.updates(tx), minimal_deposit) do
          {:ok, new_offchain_chainstate} ->
            #update was succesfull - verify the state hash
            if(ChannelTransaction.state_hash(tx) !== Chainstate.calculate_root_hash(new_offchain_chainstate)) do
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
        minimal_deposit: minimal_deposit,
        channel_id: channel_id
      }}} = create_tx

    initial_state = %ChannelStatePeer{
            fsm_state: :open,
            initiator_pubkey: initiator_pubkey,
            responder_pubkey: responder_pubkey,
            role: role,
            channel_id: channel_id,
            minimal_deposit: minimal_deposit
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
  @spec from_open(SignedTx.t(), non_neg_integer(), Channel.role()) :: ChannelStatePeer.t()
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
  @spec calculate_next_state_hash_for_tx(ChannelTransaction.channel_tx(), ChannelStatePeer.t()) :: {:ok, binary()} | {:error, String.t()}
  def calculate_next_state_hash_for_tx(tx, %ChannelStatePeer{
    minimal_deposit: minimal_deposit,
    offchain_chainstate: offchain_chainstate
  }) do
    case ChannelOffchainUpdate.apply_updates(offchain_chainstate, ChannelTransaction.updates(tx), minimal_deposit) do
      {:ok, new_offchain_chainstate} ->
        {:ok, Chainstate.calculate_root_hash(new_offchain_chainstate)}
      {:error, _} = err ->
        err
    end
  end

  @doc """
  Creates initialized channel.
  """
  @spec initialize(
          binary(),
          {{Wallet.pubkey(), non_neg_integer()}, {Wallet.pubkey(), non_neg_integer()}},
          non_neg_integer(),
          Channel.role()
        ) :: ChannelStatePeer.t()
  def initialize(
        temporary_id,
        initiator_pubkey,
        responder_pubkey,
        minimal_deposit,
        role
      ) do

    %ChannelStatePeer{
      fsm_state: :initialized,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      minimal_deposit: minimal_deposit,
      channel_id: temporary_id
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
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :initiator,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          mutually_signed_tx: [],
          highest_half_signed_tx: nil,
          minimal_deposit: minimal_deposit
        } = peer,
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
          state_hash: nil,
          minimal_deposit: minimal_deposit,
          channel_id: channel_id
        }

    case calculate_next_state_hash_for_tx(ChannelCreateTx.init(channel_create_tx_spec), peer) do
      {:ok, state_hash} ->
        create_tx_data = DataTx.init(
          ChannelCreateTx,
          Map.put(channel_create_tx_spec, :state_hash, state_hash),
          [initiator_pubkey, responder_pubkey],
          fee,
          nonce
        )
        with {:ok, half_signed_create_tx} <- SignedTx.sign_tx(create_tx_data, initiator_pubkey, priv_key) do
          {:ok,
            %ChannelStatePeer{
              peer |
              fsm_state: :awaiting_full_tx,
              mutually_signed_tx: [],
              highest_half_signed_tx: half_signed_create_tx
            },
            channel_id,
            half_signed_create_tx}
        else
          {:error, _} = err ->
            err
        end
      {:error, _} = err ->
        err
    end
  end

  def open(%ChannelStatePeer{}) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Signs provided open tx if it verifies. Can only be called in initialized state by responder. Returns altered ChannelPeerState, generated channel id and fully signed openTx.
  """
  @spec sign_open(ChannelStatePeer.t(), SignedTx.t(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def sign_open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :responder,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          mutually_signed_tx: [],
          highest_half_signed_tx: nil,
          minimal_deposit: minimal_deposit
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
      responder_amount: tx_responder_amount
    } = DataTx.payload(data_tx)

    channel_id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    cond do
      tx_initiator_amount != correct_initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initiator amount"}

      tx_responder_amount != correct_responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "#{__MODULE__}: Wrong peers"}

      true ->
        #validate the state
        case recv_half_signed_tx(
          %ChannelStatePeer{peer_state | fsm_state: :open},
          half_signed_create_tx, priv_key
        ) do
          {:ok, new_peer_state, fully_signed_create_tx} ->
            {:ok, new_peer_state, channel_id, fully_signed_create_tx}
          {:error, _} = err ->
            err
        end
    end
  end

  def sign_open(%ChannelStatePeer{}) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
    Receives a half signed transaction. Can only be called when the channel is fully open. If the transaction validates then returns a fully signed tx together with the altered state. If the received transaction is not instant then stores it and wait for min_depth confirmations.
  """
  def recv_half_signed_tx(%ChannelStatePeer{
    fsm_state: :open,
    highest_half_signed_tx: nil,
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey,
    role: :responder} = peer_state, tx, responder_privkey) do
    internal_recv_half_signed_tx(peer_state, initiator_pubkey, tx, {responder_pubkey, responder_privkey})
  end

  def recv_half_signed_tx(%ChannelStatePeer{
    fsm_state: :open,
    highest_half_signed_tx: nil,
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey,
    role: :initiator} = peer_state, tx, initiator_privkey) do
    internal_recv_half_signed_tx(peer_state, responder_pubkey, tx, {initiator_pubkey, initiator_privkey})
  end

  defp internal_recv_half_signed_tx(%ChannelStatePeer{} = peer_state, other_pubkey, tx, {own_pubkey, own_privkey}) do
    case verify_tx_and_apply(tx, peer_state, other_pubkey) do
      {:ok, new_peer_state} ->
        #The update validates on our side -> sign it and make a transition in the FSM
        case ChannelTransaction.add_signature(tx, own_pubkey, own_privkey) do
          {:ok, fully_signed_tx} ->
            if ChannelTransaction.is_instant?(fully_signed_tx) do
            {:ok,
              %ChannelStatePeer{new_peer_state |
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

    if(ChannelTransaction.state_hash(last_signed) !== ChannelTransaction.state_hash(tx)) do
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

  def recv_fully_signed_tx(%ChannelStatePeer{}, _) do
    {:error, "Unexpected 'recv_fully_signed_tx' call"}
  end

  @doc """
   This is a callback for the future transaction watcher logic. This callback must be called when the last onchain TX from this channel has reached min_depth of confirmations. Verifies if the transaction was expected and applies it to the channel state.
  """
  def recv_confirmed_tx(%ChannelStatePeer{
    fsm_state: state,
    initiator_pubkey: initiator_pubkey,
    responder_pubkey: responder_pubkey,
    highest_half_signed_tx: awaiting_tx} = peer_state, tx) when state === :awaiting_full_tx or state === :awaiting_tx_confirmed do
    if(ChannelTransaction.state_hash(awaiting_tx) !== ChannelTransaction.state_hash(tx)) do
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
  Creates a transfer on channel. Can be called by both parties on open channel when there are no unconfirmed (half-signed) transfer. Returns altered ChannelStatePeer and new half-signed offchain state.
  """
  @spec transfer(ChannelStatePeer.t(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t()} | error()
  def transfer(
        %ChannelStatePeer{fsm_state: :open, highest_mutualy_signed_offchain_tx: highest_mutualy_signed_offchain_tx, role: role} =
          peer_state,
        amount,
        priv_key
      ) do
    {:ok, new_state} = ChannelStateOffChain.transfer(highest_mutualy_signed_offchain_tx, role, amount)

    if new_state.initiator_amount < peer_state.channel_reserve ||
         new_state.responder_amount < peer_state.channel_reserve do
      {:error, "#{__MODULE__}: Too big transfer"}
    else
      new_state_signed = ChannelStateOffChain.sign(new_state, role, priv_key)

      new_peer_state = %ChannelStatePeer{
        peer_state
        | fsm_state: :update,
          highest_mutualy_signed_offchain_tx: new_state_signed
      }

      {:ok, new_peer_state, new_state_signed}
    end
  end

  def transfer(%ChannelStatePeer{} = state, _amount, _priv_key) do
    {:error, "#{__MODULE__}: Can't transfer now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Creates mutal close tx for open channel. This blocks any new transfers on channel. Returns: altered ChannelStatePeer and ChannelCloseMutalTx
  """
  @spec close(
          ChannelStatePeer.t(),
          {non_neg_integer(), non_neg_integer()},
          non_neg_integer(),
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def close(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          highest_half_signed_offchain_tx: %ChannelStateOffChain{
            channel_id: id,
            initiator_amount: initiator_amount,
            responder_amount: responder_amount
          }
        } = peer_state,
        {fee_initiator, fee_responder},
        nonce,
        priv_key
      ) do
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
              channel_id: id,
              initiator_amount: initiator_amount - fee_initiator,
              responder_amount: responder_amount - fee_responder
            },
            [initiator_pubkey, responder_pubkey],
            fee_initiator + fee_responder,
            nonce
          )

        {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, node_pubkey(peer_state), priv_key)
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
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def recv_close_tx(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          highest_half_signed_offchain_tx: %ChannelStateOffChain{
            channel_id: correct_id,
            initiator_amount: correct_initiator_amount,
            responder_amount: correct_responder_amount
          }
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

    cond do
      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "#{__MODULE__}: Invalid senders"}

      tx_id != correct_id ->
        {:error, "#{__MODULE__}: Invalid id"}

      tx_initiator_amount != correct_initiator_amount - fee_initiator ->
        {:error, "#{__MODULE__}: Invalid initiator_amount (check fee)"}

      tx_responder_amount != correct_responder_amount - fee_responder ->
        {:error, "#{__MODULE__}: Invalid responder_amount (check fee)"}

      true ->
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

        {:ok, signed_close_tx} =
          SignedTx.sign_tx(half_signed_tx, node_pubkey(peer_state), priv_key)

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
        %ChannelStatePeer{highest_half_signed_offchain_tx: our_state} = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data =
      DataTx.init(ChannelCloseSoloTx, %{state: our_state}, node_pubkey(peer_state), fee, nonce)

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, node_pubkey(peer_state), priv_key)
    {:ok, new_peer_state, our_slash_tx}
  end

  def slash(
        %ChannelStatePeer{highest_half_signed_offchain_tx: our_state} = peer_state,
        fee,
        nonce,
        pubkey,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data = DataTx.init(ChannelSlashTx, %{state: our_state}, pubkey, fee, nonce)

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, pubkey, priv_key)
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
          Wallet.pubkey(),
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t() | nil} | error()
  def slashed(
        %ChannelStatePeer{
          highest_half_signed_offchain_tx: %ChannelStateOffChain{
            sequence: best_sequence
          }
        } = peer_state,
        slash_tx,
        fee,
        nonce,
        pubkey,
        privkey
      ) do
    payload =
      slash_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()

    slash_sequence =
      case payload do
        %ChannelCloseSoloTx{} ->
          ChannelCloseSoloTx.sequence(payload)

        %ChannelSlashTx{} ->
          ChannelSlashTx.sequence(payload)
      end

    if slash_sequence < best_sequence do
      slash(peer_state, fee, nonce, pubkey, privkey)
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
        %{channel_id: id(peer_state)},
        node_pubkey(peer_state),
        fee,
        nonce
      )

    SignedTx.sign_tx(data, node_pubkey(peer_state), priv_key)
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
  @spec node_pubkey(ChannelStatePeer.t()) :: Wallet.pubkey()
  def node_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def node_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end
end
