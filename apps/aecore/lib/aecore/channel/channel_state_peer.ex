defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Module defining the structure of the Channel Peer state
  """

  alias Aecore.Channel.{
    ChannelStateOffChain,
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelCreateTx
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

  @type fsm_state :: :initialized | :half_signed | :signed | :open | :update | :closing | :closed

  @type t :: %ChannelStatePeer{
          fsm_state: fsm_state(),
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          role: Channel.role(),
          highest_state: ChannelStateOffChain.t(),
          highest_signed_state: ChannelStateOffChain.t(),
          channel_reserve: non_neg_integer()
        }

  @type error :: {:error, binary()}

  defstruct [
    :fsm_state,
    :initiator_pubkey,
    :responder_pubkey,
    :role,
    :highest_state,
    :highest_signed_state,
    :channel_reserve
  ]

  require Logger

  use ExConstructor

  @spec id(ChannelStatePeer.t()) :: binary()
  def id(%ChannelStatePeer{highest_signed_state: %ChannelStateOffChain{channel_id: id}}), do: id

  @doc """
  Creates a channel from a signed channel state.
  """
  @spec from_state(
          ChannelStateOffChain.t(),
          Keys.pubkey(),
          Keys.pubkey(),
          non_neg_integer(),
          Channel.role()
        ) :: ChannelStatePeer.t()
  def from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role) do
    %ChannelStatePeer{
      fsm_state: :open,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      highest_state: state,
      highest_signed_state: state,
      channel_reserve: channel_reserve
    }
  end

  @doc """
  Creates a channel from an open transaction assuming no transactions in channel.
  """
  @spec from_open(SignedTx.t(), non_neg_integer(), Channel.role()) :: ChannelStatePeer.t()
  def from_open(open_tx, channel_reserve, role) do
    data_tx = SignedTx.data_tx(open_tx)

    %ChannelCreateTx{
      initiator_amount: initiator_amount,
      responder_amount: responder_amount
    } = DataTx.payload(data_tx)

    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id = ChannelStateOnChain.id(data_tx)

    state =
      ChannelStateOffChain.create(
        id,
        0,
        initiator_amount,
        responder_amount
      )

    from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role)
  end

  @doc """
  Creates a channel from an open transaction and signed state.
  """
  @spec from_open_and_state(
          SignedTx.t(),
          ChannelStateOffChain.t(),
          non_neg_integer(),
          Channel.role()
        ) :: ChannelPeerState.t()
  def from_open_and_state(open_tx, state, channel_reserve, role) do
    data_tx = SignedTx.data_tx(open_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role)
  end

  @doc """
  Creates an initialized channel.
  """
  @spec initialize(
          binary(),
          {{Keys.pubkey(), non_neg_integer()}, {Keys.pubkey(), non_neg_integer()}},
          non_neg_integer(),
          Channel.role()
        ) :: ChannelStatePeer.t()
  def initialize(
        temporary_id,
        {{initiator_pubkey, initiator_amount}, {responder_pubkey, responder_amount}},
        channel_reserve,
        role
      ) do
    initial_state =
      ChannelStateOffChain.create(temporary_id, 0, initiator_amount, responder_amount)

    %ChannelStatePeer{
      fsm_state: :initialized,
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      role: role,
      highest_state: initial_state,
      highest_signed_state: nil,
      channel_reserve: channel_reserve
    }
  end

  @doc """
  Creates a channel open tx. Can only be called in initialized state by the initiator. Changes fsm state to half_signed. Specified fee and nonce are for the created tx. Returns an altered ChannelPeerState, generated channel id and open tx.
  """
  @spec open(
          ChannelStatePeer.t(),
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
          highest_state: %ChannelStateOffChain{
            initiator_amount: initiator_amount,
            responder_amount: responder_amount
          }
        } = peer_state,
        locktime,
        fee,
        nonce,
        priv_key
      ) do
    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    zero_state = ChannelStateOffChain.create(id, 0, initiator_amount, responder_amount)

    open_tx_data =
      DataTx.init(
        ChannelCreateTx,
        %{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          locktime: locktime
        },
        [initiator_pubkey, responder_pubkey],
        fee,
        nonce
      )

    new_peer_state = %ChannelStatePeer{
      peer_state
      | fsm_state: :half_signed,
        highest_state: zero_state,
        highest_signed_state: zero_state
    }

    with {:ok, half_signed_open_tx} <- SignedTx.sign_tx(open_tx_data, initiator_pubkey, priv_key) do
      {:ok, new_peer_state, id, half_signed_open_tx}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def open(%ChannelStatePeer{}) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Signs provided open tx if it verifies. Can only be called in initialized state by the responder. Returns an altered ChannelPeerState, generated channel id and fully signed open tx.
  """
  @spec sign_open(ChannelStatePeer.t(), SignedTx.t(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def sign_open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :responder,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          highest_state: %ChannelStateOffChain{
            initiator_amount: correct_initiator_amount,
            responder_amount: correct_responder_amount
          }
        } = peer_state,
        half_signed_open_tx,
        priv_key
      ) do
    data_tx = SignedTx.data_tx(half_signed_open_tx)
    nonce = DataTx.nonce(data_tx)

    %ChannelCreateTx{
      initiator_amount: tx_initiator_amount,
      responder_amount: tx_responder_amount
    } = DataTx.payload(data_tx)

    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)

    cond do
      tx_initiator_amount != correct_initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initiator amount"}

      tx_responder_amount != correct_responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "#{__MODULE__}: Wrong peers"}

      true ->
        zero_state = ChannelStateOffChain.create(id, 0, tx_initiator_amount, tx_responder_amount)

        {:ok, fully_signed_open_tx} =
          SignedTx.sign_tx(half_signed_open_tx, responder_pubkey, priv_key)

        new_peer_state = %ChannelStatePeer{
          peer_state
          | fsm_state: :signed,
            highest_state: zero_state,
            highest_signed_state: zero_state
        }

        {:ok, new_peer_state, id, fully_signed_open_tx}
    end
  end

  def sign_open(%ChannelStatePeer{}) do
    {:error, "#{__MODULE__}: Invalid call"}
  end

  @doc """
  Changes channel state to open from signed and half_signed. Should only be called when a ChannelCreateTx is mined.
  """
  @spec opened(ChannelStatePeer.t()) :: ChannelStatePeer.t()
  def opened(%ChannelStatePeer{fsm_state: :signed} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :open}
  end

  def opened(%ChannelStatePeer{fsm_state: :half_signed} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :open}
  end

  def opened(%ChannelStatePeer{} = state) do
    Logger.warn("Unexpected 'opened' call")
    state
  end

  @doc """
  Creates a transfer on a channel. Can be called by both parties on open channel when there are no unconfirmed (half-signed) transfers. Returns an altered ChannelStatePeer and new half-signed offchain state.
  """
  @spec transfer(ChannelStatePeer.t(), non_neg_integer(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t()} | error()
  def transfer(
        %ChannelStatePeer{fsm_state: :open, highest_state: highest_state, role: role} =
          peer_state,
        amount,
        priv_key
      ) do
    {:ok, new_state} = ChannelStateOffChain.transfer(highest_state, role, amount)

    if new_state.initiator_amount < peer_state.channel_reserve ||
         new_state.responder_amount < peer_state.channel_reserve do
      {:error, "#{__MODULE__}: Too big transfer"}
    else
      new_state_signed = ChannelStateOffChain.sign(new_state, role, priv_key)

      new_peer_state = %ChannelStatePeer{
        peer_state
        | fsm_state: :update,
          highest_state: new_state_signed
      }

      {:ok, new_peer_state, new_state_signed}
    end
  end

  def transfer(%ChannelStatePeer{} = state, _amount, _priv_key) do
    {:error, "#{__MODULE__}: Can't transfer now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Handles incoming ChannelOffChainState. If incoming state is a half signed transfer validates it and signs it. If incoming state is fully signed and has higher sequence then current then stores it. Returns an altered ChannelPeerState and if it signed a half signed state - fully signed state, else - nil.
  """
  @spec recv_state(ChannelStatePeer.t(), ChannelStateOffChain.t(), Keys.sign_priv_key()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t() | nil} | error()
  def recv_state(%ChannelStatePeer{fsm_state: :open} = peer_state, new_state, priv_key) do
    with {:ok, new_peer_state, nil} <- recv_full_state(peer_state, new_state) do
      {:ok, new_peer_state, nil}
    else
      {:error, _reason} ->
        recv_half_state(peer_state, new_state, priv_key)
    end
  end

  def recv_state(%ChannelStatePeer{fsm_state: :update} = peer_state, new_state, _priv_key) do
    recv_full_state(peer_state, new_state)
  end

  def recv_state(%ChannelStatePeer{} = state) do
    {:error, "#{__MODULE__}: Can't receive state now; channel state is #{state.fsm_state}"}
  end

  defp recv_full_state(
         %ChannelStatePeer{
           highest_signed_state: highest_signed_state,
           highest_state: highest_state
         } = peer_state,
         new_state
       ) do
    pubkeys = {peer_state.initiator_pubkey, peer_state.responder_pubkey}

    with :ok <-
           ChannelStateOffChain.validate_full_update(highest_signed_state, new_state, pubkeys) do
      if highest_state.sequence <= new_state.sequence do
        {:ok,
         %ChannelStatePeer{
           peer_state
           | fsm_state: :open,
             highest_signed_state: new_state,
             highest_state: new_state
         }, nil}
      else
        {:ok, %ChannelStatePeer{peer_state | highest_signed_state: new_state}, nil}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_half_state(
         %ChannelStatePeer{highest_signed_state: prev_state} = peer_state,
         new_state,
         priv_key
       ) do
    pubkeys = {peer_state.initiator_pubkey, peer_state.responder_pubkey}

    with :ok <-
           ChannelStateOffChain.validate_half_update(
             prev_state,
             new_state,
             pubkeys,
             peer_state.role
           ) do
      signed_new_state = ChannelStateOffChain.sign(new_state, peer_state.role, priv_key)

      new_peer_state = %ChannelStatePeer{
        peer_state
        | highest_signed_state: signed_new_state,
          highest_state: signed_new_state
      }

      with :ok <- ChannelStateOffChain.validate(signed_new_state, pubkeys) do
        {:ok, new_peer_state, signed_new_state}
      else
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a mutal close tx for an open channel. This blocks any new transfers on the channel. Returns: altered ChannelStatePeer and ChannelCloseMutalTx
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
          highest_signed_state: %ChannelStateOffChain{
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
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def recv_close_tx(
        %ChannelStatePeer{
          fsm_state: :open,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          highest_signed_state: %ChannelStateOffChain{
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
  Changes the channel state to closed. Should only be called when a ChannelCloseMutalTx is mined.
  """
  def closed(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  @doc """
  Creates a solo close tx for a channel. Should only be called when no solo close tx-s were mined for this channel. Returns altered an ChannelStatePeer and ChannelCloseSoloTx
  """
  @spec solo_close(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def solo_close(
        %ChannelStatePeer{highest_signed_state: our_state} = peer_state,
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
        %ChannelStatePeer{highest_signed_state: our_state} = peer_state,
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
  Handles mined ChannelSlashTx and ChannelCloseSoloTx. Provided fee and nonce are for potentially created SlashTx. Pubkey and Privkey don't have to match any of the channel parties. Returns altered ChannelPeerState and ChannelSlashTx if we have higher signed state.
  """
  @spec slashed(
          ChannelStatePeer.t(),
          SignedTx.t(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.pubkey(),
          Keys.sign_priv_key()
        ) :: {:ok, ChannelStatePeer.t(), SignedTx.t() | nil} | error()
  def slashed(
        %ChannelStatePeer{
          highest_signed_state: %ChannelStateOffChain{
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
  Creates a channel settle tx.
  """
  @spec settle(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Keys.sign_priv_key()) ::
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
  Changes the channel state to closed. Should only be called when a ChannelSettleTx is mined.
  """
  @spec settled(ChannelStatePeer.t()) :: ChannelStatePeer.t()
  def settled(%ChannelStatePeer{} = peer_state) do
    %ChannelStatePeer{peer_state | fsm_state: :closed}
  end

  @doc """
  Returns our pubkey from the channel.
  """
  @spec node_pubkey(ChannelStatePeer.t()) :: Keys.pubkey()
  def node_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def node_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end
end
