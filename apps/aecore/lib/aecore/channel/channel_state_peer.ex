defmodule Aecore.Channel.ChannelStatePeer do
  @moduledoc """
  Structure of Channel Peer State
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

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Tx.{SignedTx, DataTx}

  @type fsm_state :: :initialized | :half_signed | :signed | :open | :update | :closing | :closed

  @type t :: %ChannelStatePeer{
          fsm_state: fsm_state(),
          initiator_pubkey: Wallet.pubkey(),
          responder_pubkey: Wallet.pubkey(),
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

  @spec role(ChannelStatePeer.t()) :: Channel.role()
  def role(%ChannelStatePeer{role: role}) do
    role
  end

  @spec state(ChannelStatePeer.t()) :: ChannelStateOffChain.t()
  def state(%ChannelStatePeer{highest_signed_state: state}) do
    state
  end

  @spec fsm_state(ChannelStatePeer.t()) :: fsm_state()
  def fsm_state(%ChannelStatePeer{fsm_state: fsm_state}) do
    fsm_state
  end

  @spec id(ChannelStatePeer.t()) :: binary()
  def id(peer_state) do
    peer_state
    |> state()
    |> ChannelStateOffChain.id()
  end

  @doc """
  Creates channel from signed channel state.
  """
  @spec from_state(
          ChannelStateOffChain.t(),
          Wallet.pubkey(),
          Wallet.pubkey(),
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
  Creates channel from open transaction assuming no transactions in channel.
  """
  @spec from_open(SignedTx.t(), non_neg_integer(), Channel.role()) :: ChannelStatePeer.t()
  def from_open(open_tx, channel_reserve, role) do
    data_tx = SignedTx.data_tx(open_tx)
    open_tx = DataTx.payload(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id = ChannelStateOnChain.id(data_tx)

    state =
      ChannelStateOffChain.create(
        id,
        0,
        ChannelCreateTx.initiator_amount(open_tx),
        ChannelCreateTx.responder_amount(open_tx)
      )

    from_state(state, initiator_pubkey, responder_pubkey, channel_reserve, role)
  end

  @doc """
  Creates channel from open transaction and signed state.
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
  Creates initialized channel.
  """
  @spec initialize(
          binary(),
          list(Wallet.pubkey()),
          list(non_neg_integer()),
          non_neg_integer(),
          Channel.role()
        ) :: ChannelStatePeer.t()
  def initialize(
        temporary_id,
        [initiator_pubkey, responder_pubkey],
        [initiator_amount, responder_amount],
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
  Creates channel open tx. Can only be called in initialized state by initiator. Changes fsm state to half_signed. Specified fee and nonce are for the created tx. Returns altered ChannelPeerState, generated channel id, open tx.
  """
  @spec create_open(
          ChannelStatePeer.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Wallet.privkey()
        ) :: {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def create_open(
        %ChannelStatePeer{
          fsm_state: :initialized,
          role: :initiator,
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey
        } = peer_state,
        locktime,
        fee,
        nonce,
        priv_key
      ) do
    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
    initiator_amount = ChannelStateOffChain.initiator_amount(peer_state.highest_state)
    responder_amount = ChannelStateOffChain.responder_amount(peer_state.highest_state)

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

  def create_open(%ChannelStatePeer{}) do
    {:error, "Invalid call"}
  end

  @doc """
  Signs provided open tx if it verifies. Can only be called in initialized state by responder. Returns altered ChannelPeerState, generated channel id and fully signed openTx.
  """
  @spec sign_open(ChannelStatePeer.t(), SignedTx.t(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), binary(), SignedTx.t()} | error()
  def sign_open(
        %ChannelStatePeer{fsm_state: :initialized, role: :responder, highest_state: our_state} =
          peer_state,
        half_signed_open_tx,
        priv_key
      ) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey
    data_tx = SignedTx.data_tx(half_signed_open_tx)
    nonce = DataTx.nonce(data_tx)
    open_payload = DataTx.payload(data_tx)

    id = ChannelStateOnChain.id(initiator_pubkey, responder_pubkey, nonce)
    initiator_amount = ChannelStateOffChain.initiator_amount(our_state)
    responder_amount = ChannelStateOffChain.responder_amount(our_state)

    cond do
      ChannelCreateTx.initiator_amount(open_payload) != initiator_amount ->
        {:error, "Wrong initiator amount"}

      ChannelCreateTx.responder_amount(open_payload) != responder_amount ->
        {:error, "Wrong responder amount"}

      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "Wrong peers"}

      true ->
        zero_state = ChannelStateOffChain.create(id, 0, initiator_amount, responder_amount)

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
    {:error, "Invalid call"}
  end

  @doc """
  Changes channel state to open from signed and half_signed. Should only be called when ChannelCreateTx is mined.
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
  Creates a transfer on channel. Can be called by both parties on open channel when there are no unconfirmed (half-signed) transfer. Returns altered ChannelStatePeer and new half-signed offchain state.
  """
  @spec transfer(ChannelStatePeer.t(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), ChannelStateOffChain.t()} | error()
  def transfer(
        %ChannelStatePeer{fsm_state: :open, highest_state: highest_state, role: role} =
          peer_state,
        amount,
        priv_key
      ) do
    {:ok, new_state} = ChannelStateOffChain.transfer(highest_state, role, amount)

    if ChannelStateOffChain.initiator_amount(new_state) < peer_state.channel_reserve ||
         ChannelStateOffChain.responder_amount(new_state) < peer_state.channel_reserve do
      {:error, "Too big transfer"}
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
    {:error, "Can't transfer now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Handles incoming ChannelOffChainState. If incoming state is a half signed transfer validates it and signs it. If incoming state is fully signed and has higher sequence then current then stores it. Returns altered ChannelPeerState and if it signed a half signed state: fully signed state else nil.
  """
  @spec recv_state(ChannelStatePeer.t(), ChannelStateOffChain.t(), Wallet.privkey()) ::
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
    {:error, "Can't receive state now; channel state is #{state.fsm_state}"}
  end

  defp recv_full_state(
         %ChannelStatePeer{
           highest_signed_state: highest_signed_state,
           highest_state: highest_state
         } = peer_state,
         new_state
       ) do
    pubkeys = [peer_state.initiator_pubkey, peer_state.responder_pubkey]

    with :ok <-
           ChannelStateOffChain.validate_full_update(highest_signed_state, new_state, pubkeys) do
      if ChannelStateOffChain.sequence(highest_state) <= ChannelStateOffChain.sequence(new_state) do
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
    pubkeys = [peer_state.initiator_pubkey, peer_state.responder_pubkey]

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
  Creates mutal close tx for open channel. This blocks any new transfers on channel. Returns: altered ChannelStatePeer and ChannelCloseMutalTx
  """
  @spec close(ChannelStatePeer.t(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def close(
        %ChannelStatePeer{fsm_state: :open, highest_signed_state: state} = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey

    close_tx =
      DataTx.init(
        ChannelCloseMutalTx,
        %{
          channel_id: ChannelStateOffChain.id(state),
          initiator_amount: ChannelStateOffChain.initiator_amount(state),
          responder_amount: ChannelStateOffChain.responder_amount(state)
        },
        [initiator_pubkey, responder_pubkey],
        fee,
        nonce
      )

    {:ok, close_signed_tx} = SignedTx.sign_tx(close_tx, my_pubkey(peer_state), priv_key)
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    {:ok, new_peer_state, close_signed_tx}
  end

  def close(%ChannelStatePeer{} = state) do
    {:error, "Can't close now; channel state is #{state.fsm_state}"}
  end

  @doc """
  Handles incoming channel close tx. If our highest state matches the incoming signs the tx and blocks any new transfers. Returns altered ChannelStatePeer and signed ChannelCloseMutalTx
  """
  @spec recv_close_tx(ChannelStatePeer.t(), SignedTx.t(), Wallet.privkey()) ::
          {:ok, ChannelStatePeer.t(), SignedTx.t()} | error()
  def recv_close_tx(
        %ChannelStatePeer{fsm_state: :open, highest_signed_state: state} = peer_state,
        half_signed_tx,
        priv_key
      ) do
    initiator_pubkey = peer_state.initiator_pubkey
    responder_pubkey = peer_state.responder_pubkey
    data_tx = SignedTx.data_tx(half_signed_tx)
    close_tx = DataTx.payload(data_tx)

    cond do
      DataTx.senders(data_tx) != [initiator_pubkey, responder_pubkey] ->
        {:error, "Invalid senders"}

      ChannelCloseMutalTx.channel_id(close_tx) != ChannelStateOffChain.id(state) ->
        {:error, "Invalid id"}

      ChannelCloseMutalTx.initiator_amount(close_tx) !=
          ChannelStateOffChain.initiator_amount(state) ->
        {:error, "Invalid initiator_amount"}

      ChannelCloseMutalTx.responder_amount(close_tx) !=
          ChannelStateOffChain.responder_amount(state) ->
        {:error, "Invalid responder_amount"}

      true ->
        new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}
        {:ok, signed_close_tx} = SignedTx.sign_tx(half_signed_tx, my_pubkey(peer_state), priv_key)
        {:ok, new_peer_state, signed_close_tx}
    end
  end

  def recv_close_tx(%ChannelStatePeer{} = state) do
    {:error, "Can't receive close tx now; channel state is #{state.fsm_state}"}
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
        %ChannelStatePeer{highest_signed_state: our_state} = peer_state,
        fee,
        nonce,
        priv_key
      ) do
    new_peer_state = %ChannelStatePeer{peer_state | fsm_state: :closing}

    data = DataTx.init(ChannelCloseSoloTx, %{state: our_state}, my_pubkey(peer_state), fee, nonce)

    {:ok, our_slash_tx} = SignedTx.sign_tx(data, my_pubkey(peer_state), priv_key)
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
        %ChannelStatePeer{highest_signed_state: our_state} = peer_state,
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

    if slash_sequence < ChannelStateOffChain.sequence(our_state) do
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
        ChannelStatePeer.my_pubkey(peer_state),
        fee,
        nonce
      )

    SignedTx.sign_tx(data, ChannelStatePeer.my_pubkey(peer_state), priv_key)
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
  @spec my_pubkey(ChannelStatePeer.t()) :: Wallet.pubkey()
  def my_pubkey(%ChannelStatePeer{role: :initiator, initiator_pubkey: pubkey}) do
    pubkey
  end

  def my_pubkey(%ChannelStatePeer{role: :responder, responder_pubkey: pubkey}) do
    pubkey
  end
end
