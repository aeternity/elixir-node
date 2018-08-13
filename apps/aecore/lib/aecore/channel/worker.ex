defmodule Aecore.Channel.Worker do
  @moduledoc """
  Module for managing Channels
  """

  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStatePeer

  alias Aecore.Channel.Tx.{
    ChannelCloseMutalTx,
    ChannelCloseSoloTx,
    ChannelSlashTx,
    ChannelSettleTx,
    ChannelCreateTx
  }

  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys.Wallet
  alias Aeutil.Events

  use GenServer

  require Logger

  @type role :: :initiator | :responder

  @typedoc """
  State is map channel_id -> channel_peer_state
  """
  @type state :: %{binary() => ChannelStatePeer.t()}

  @type error :: {:error, binary()}

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    Events.subscribe(:new_top_block)
    {:ok, %{}}
  end

  @doc """
  Notifies channel manager about new mined tx
  """
  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelCreateTx}} = tx) do
    opened(tx)
  end

  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelCloseMutalTx}} = tx) do
    closed(tx)
  end

  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelCloseSoloTx}} = _tx) do
    # TODO
    :ok
  end

  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelSlashTx}} = _tx) do
    # TODO
    :ok
  end

  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelSettleTx}} = tx) do
    closed(tx)
  end

  def new_tx_mined(%SignedTx{data: %DataTx{type: ChannelSnapshotSoloTx}} = _tx) do
    # ChannelSnapshotSoloTx requires no action
    :ok
  end

  def new_tx_mined(%SignedTx{}) do
    # We don't care about this tx
    :ok
  end

  @doc """
  Imports channels from ChannelStatePeer object. Useful for storage
  """
  @spec import_channel(ChannelStatePeer.t()) :: :ok | error()
  def import_channel(%ChannelStatePeer{} = channel_state) do
    id = ChannelStatePeer.id(channel_state)
    GenServer.call(__MODULE__, {:import_channel, id, channel_state})
  end

  @doc """
  Import channel from open tx. Assumes no transactions were made
  """
  @spec import_from_open(SignedTx.t(), non_neg_integer(), role()) :: :ok | error()
  def import_from_open(%SignedTx{} = open_tx, reserve, role)
      when is_integer(reserve) and is_atom(role) do
    peer_state = ChannelStatePeer.from_open(open_tx, reserve, role)
    import_channel(peer_state)
  end

  @doc """
  Imports channel from open tx and ChannelStateOffChain.
  """
  @spec import_from_open_and_state(
          SignedTx.t(),
          ChannelStateOffChain.t(),
          non_neg_integer(),
          role()
        ) :: :ok | error()
  def import_from_open_and_state(
        %SignedTx{} = open_tx,
        %ChannelStateOffChain{} = state,
        reserve,
        role
      )
      when is_integer(reserve) and is_atom(role) do
    peer_state = ChannelStatePeer.from_open_and_state(open_tx, state, reserve, role)
    import_channel(peer_state)
  end

  @doc """
  Initializes channel with temporary ID. This has to be called for every channel by both :initiator and :responder.
  """
  @spec initialize(
          binary(),
          {{Wallet.pubkey(), non_neg_integer()}, {Wallet.pubkey(), non_neg_integer()}},
          role(),
          non_neg_integer()
        ) :: :ok | error()
  def initialize(temporary_id, {{_, _}, {_, _}} = parties, role, channel_reserve)
      when is_binary(temporary_id) and is_atom(role) and is_integer(channel_reserve) do
    GenServer.call(
      __MODULE__,
      {:initialize, temporary_id, parties, role, channel_reserve}
    )
  end

  @doc """
  Creates open transaction. Can only be called once per channel by :initiator. Returns pair: generated channelID, half signed SignedTx.
  """
  @spec open(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Wallet.privkey()
        ) :: {:ok, binary(), SignedTx.t()} | error()
  def open(temporary_id, locktime, fee, nonce, priv_key)
      when is_binary(temporary_id) and is_integer(locktime) and is_integer(fee) and
             is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:open, temporary_id, locktime, fee, nonce, priv_key})
  end

  @doc """
  Signs open transaction. Can only be called once per channel by :responder. Returns fully signed SignedTx and adds it to Pool.
  """
  @spec sign_open(binary(), SignedTx.t(), Wallet.privkey()) ::
          {:ok, binary(), SignedTx.t()} | error()
  def sign_open(temporary_id, %SignedTx{} = open_tx, priv_key)
      when is_binary(temporary_id) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:sign_open, temporary_id, open_tx, priv_key})
  end

  @doc """
  Notifies Channels Manager about confirmed channel open tx. Called by block validation stack.
  """
  @spec opened(SignedTx.t()) :: :ok
  def opened(%SignedTx{} = open_tx) do
    case GenServer.call(__MODULE__, {:opened, open_tx}) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.warn(reason)
        error
    end
  end

  @doc """
  Transfers amount to other peer in channel. Returns half-signed channel off-chain state. Can only be called on open channel.
  """
  @spec transfer(binary(), non_neg_integer(), Wallet.privkey()) ::
          {:ok, ChannelStateOffChain.t()} | error()
  def transfer(channel_id, amount, priv_key)
      when is_binary(channel_id) and is_integer(amount) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:transfer, channel_id, amount, priv_key})
  end

  @doc """
  Handles received channel state. If it's half signed and validates: signs it and returns it.
  """
  @spec recv_state(ChannelStateOffChain.t(), Wallet.privkey()) ::
          {:ok, ChannelStateOffChain.t() | nil} | error()
  def recv_state(%ChannelStateOffChain{} = recv_state, priv_key) when is_binary(priv_key) do
    GenServer.call(__MODULE__, {:recv_state, recv_state, priv_key})
  end

  @doc """
  Creates channel close transaction. This also blocks any new transactions from happening on channel.
  """
  @spec close(
          binary(),
          {non_neg_integer(), non_neg_integer()},
          non_neg_integer(),
          Wallet.privkey()
        ) :: {:ok, SignedTx.t()} | error()
  def close(channel_id, {_, _} = fees, nonce, priv_key)
      when is_binary(channel_id) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:close, channel_id, fees, nonce, priv_key})
  end

  @doc """
  Handles received half signed close tx. If it validates returns fully signed close tx and adds it to Pool.
  """
  @spec recv_close_tx(
          binary(),
          SignedTx.t(),
          {non_neg_integer(), non_neg_integer()},
          Wallet.privkey()
        ) :: {:ok, SignedTx.t()} | error()
  def recv_close_tx(channel_id, %SignedTx{} = close_tx, {_, _} = fees, priv_key)
      when is_binary(channel_id) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:recv_close_tx, channel_id, close_tx, fees, priv_key})
  end

  @doc """
  Notifies Channel Manager about close tx being mined.
  """
  @spec closed(SignedTx.t()) :: :ok | error()
  def closed(%SignedTx{} = close_tx) do
    GenServer.call(__MODULE__, {:closed, close_tx})
  end

  @doc """
  Solo closes channel. Creates solo close Tx and adds it to the pool.
  """
  @spec solo_close(binary(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          :ok | error()
  def solo_close(channel_id, fee, nonce, priv_key)
      when is_binary(channel_id) and is_integer(fee) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:solo_close, channel_id, fee, nonce, priv_key})
  end

  @doc """
  Slashes channel. Creates slash Tx and adds it to the pool.
  """
  @spec slash(binary(), non_neg_integer(), non_neg_integer(), Wallet.pubkey(), Wallet.privkey()) ::
          :ok | error()
  def slash(channel_id, fee, nonce, pubkey, priv_key)
      when is_binary(channel_id) and is_integer(fee) and is_integer(nonce) and is_binary(pubkey) and
             is_binary(priv_key) do
    GenServer.call(__MODULE__, {:slash, channel_id, fee, nonce, pubkey, priv_key})
  end

  @doc """
  Notifies channel manager about mined slash or solo close transaction. If channel Manager has newer state for corresponding channel it creates a slash transaction and add it to pool.
  """
  @spec slashed(
          SignedTx.t(),
          non_neg_integer(),
          non_neg_integer(),
          Wallet.pubkey(),
          Wallet.privkey()
        ) :: :ok | error()
  def slashed(%SignedTx{} = slash_tx, fee, nonce, pubkey, priv_key)
      when is_integer(fee) and is_integer(nonce) and is_binary(pubkey) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:slashed, slash_tx, fee, nonce, pubkey, priv_key})
  end

  @doc """
  Creates settle transaction and adds it to the pool
  """
  @spec settle(binary(), non_neg_integer(), non_neg_integer(), Wallet.privkey()) ::
          :ok | :error | error()
  def settle(channel_id, fee, nonce, priv_key)
      when is_binary(channel_id) and is_integer(fee) and is_integer(nonce) and is_binary(priv_key) do
    with {:ok, peer_state} <- get_channel(channel_id),
         {:ok, tx} <- ChannelStatePeer.settle(peer_state, fee, nonce, priv_key) do
      Pool.add_transaction(tx)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Notifies channel manager about mined settle tx.
  """
  @spec settled(SignedTx.t()) :: :ok | error()
  def settled(%SignedTx{} = settle_tx) do
    GenServer.call(__MODULE__, {:settled, settle_tx})
  end

  @doc """
  Returns map of all ChannelStatePeer objects.
  """
  @spec get_all_channels :: %{binary() => ChannelStatePeer.t()}
  def get_all_channels do
    GenServer.call(__MODULE__, :get_all_channels)
  end

  @doc """
  Returns channel peer state of channel with specified id.
  """
  @spec get_channel(binary()) :: {:ok, ChannelStatePeer.t()} | error()
  def get_channel(channel_id) when is_binary(channel_id) do
    GenServer.call(__MODULE__, {:get_channel, channel_id})
  end

  ## Server side
  #
  def handle_call({:import_channel, channel_id, channel_state}, _from, state) do
    {:reply, :ok, Map.put(state, channel_id, channel_state)}
  end

  def handle_call(
        {:initialize, temporary_id, parties, role, channel_reserve},
        _from,
        state
      ) do
    peer_state = ChannelStatePeer.initialize(temporary_id, parties, channel_reserve, role)

    {:reply, :ok, Map.put(state, temporary_id, peer_state)}
  end

  def handle_call({:open, temporary_id, locktime, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, temporary_id)

    {:ok, new_peer_state, new_id, open_tx} =
      ChannelStatePeer.open(peer_state, locktime, fee, nonce, priv_key)

    new_state =
      state
      |> Map.drop([temporary_id])
      |> Map.put(new_id, new_peer_state)

    {:reply, {:ok, new_id, open_tx}, new_state}
  end

  def handle_call({:sign_open, temporary_id, open_tx, priv_key}, _from, state) do
    peer_state = Map.get(state, temporary_id)

    with {:ok, new_peer_state, id, signed_open_tx} <-
           ChannelStatePeer.sign_open(peer_state, open_tx, priv_key),
         :ok <- Pool.add_transaction(signed_open_tx) do
      new_state =
        state
        |> Map.drop([temporary_id])
        |> Map.put(id, new_peer_state)

      {:reply, {:ok, id, signed_open_tx}, new_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      :error ->
        {:reply, {:error, "#{__MODULE__}: Pool error"}, state}
    end
  end

  def handle_call({:opened, open_tx}, _from, state) do
    id = ChannelStateOnChain.id(SignedTx.data_tx(open_tx))

    if Map.has_key?(state, id) do
      peer_state = Map.get(state, id)
      new_peer_state = ChannelStatePeer.opened(peer_state)
      {:reply, :ok, Map.put(state, id, new_peer_state)}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:transfer, id, amount, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, offchain_state} <-
           ChannelStatePeer.transfer(peer_state, amount, priv_key) do
      {:reply, {:ok, offchain_state}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:recv_state, %ChannelStateOffChain{channel_id: id} = recv_state, priv_key},
        _from,
        state
      ) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, offchain_state} <-
           ChannelStatePeer.recv_state(peer_state, recv_state, priv_key) do
      {:reply, {:ok, offchain_state}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:close, id, fees, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, close_tx} <-
           ChannelStatePeer.close(peer_state, fees, nonce, priv_key) do
      {:reply, {:ok, close_tx}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:recv_close_tx, id, close_tx, fees, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, signed_close_tx} <-
           ChannelStatePeer.recv_close_tx(peer_state, close_tx, fees, priv_key),
         :ok <- Pool.add_transaction(signed_close_tx) do
      {:reply, {:ok, signed_close_tx}, Map.put(state, id, new_peer_state)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      :error ->
        {:reply,
         {:error, "#{__MODULE__}: Transaction Pool error (Invalid received tx signature?)"},
         state}
    end
  end

  def handle_call({:closed, close_tx}, _from, state) do
    payload =
      close_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()

    id =
      case payload do
        %ChannelCloseMutalTx{channel_id: id} ->
          id

        %ChannelSettleTx{channel_id: id} ->
          id
      end

    if Map.has_key?(state, id) do
      peer_state = Map.get(state, id)
      new_peer_state = ChannelStatePeer.closed(peer_state)
      {:reply, :ok, Map.put(state, id, new_peer_state)}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:solo_close, channel_id, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, channel_id)

    with {:ok, new_peer_state, tx} <-
           ChannelStatePeer.solo_close(peer_state, fee, nonce, priv_key),
         :ok <- Pool.add_transaction(tx) do
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    else
      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, "#{__MODULE__}: Pool error"}
    end
  end

  def handle_call({:slash, channel_id, fee, nonce, pubkey, priv_key}, _from, state) do
    peer_state = Map.get(state, channel_id)

    with {:ok, new_peer_state, tx} <-
           ChannelStatePeer.slash(peer_state, fee, nonce, pubkey, priv_key),
         :ok <- Pool.add_transaction(tx) do
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    else
      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, "#{__MODULE__}: Pool error"}
    end
  end

  def handle_call({:slashed, slash_tx, fee, nonce, pubkey, priv_key}, _from, state) do
    data_tx = SignedTx.data_tx(slash_tx)

    channel_id =
      case DataTx.payload(data_tx) do
        %ChannelCloseSoloTx{} = payload ->
          ChannelCloseSoloTx.channel_id(payload)

        %ChannelSlashTx{} = payload ->
          ChannelSlashTx.channel_id(payload)
      end

    if Map.has_key?(state, channel_id) do
      peer_state = Map.get(state, channel_id)

      {:ok, new_peer_state, tx} =
        ChannelStatePeer.slashed(peer_state, slash_tx, fee, nonce, pubkey, priv_key)

      if tx != nil do
        case Pool.add_transaction(tx) do
          :ok ->
            {:reply, :ok, Map.put(state, channel_id, new_peer_state)}

          :error ->
            {:reply, {:error, "#{__MODULE__}: Pool error"}, state}
        end
      else
        {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
      end
    else
      {:reply, {:error, "#{__MODULE__}: Unknown channel"}, state}
    end
  end

  @doc """
    Submits a snapshot of the most recent state of a channel
  """
  def handle_call({:snapshot, channel_id, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, channel_id)

    with {:ok, tx} <-
      ChannelStatePeer.snapshot(peer_state, fee, nonce, priv_key),
         :ok <- Pool.add_transaction(tx) do
        {:reply, :ok, state}
      else
      {:error, _} = err ->
        {:reply, err, state}

      :error ->
        {:error, "#{__MODULE__}: Pool error"}
    end
  end

  def handle_call({:settled, settle_tx}, _from, state) do
    %ChannelSettleTx{channel_id: channel_id} =
      settle_tx
      |> SignedTx.data_tx()
      |> DataTx.payload()

    if Map.has_key?(state, channel_id) do
      new_peer_state = ChannelStatePeer.settled(Map.get(state, channel_id))
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:get_all_channels, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_channel, channel_id}, _from, state) do
    if Map.has_key?(state, channel_id) do
      {:reply, {:ok, Map.get(state, channel_id)}, state}
    else
      {:reply, {:error, "#{__MODULE__}: No such channel"}, state}
    end
  end

  def handle_info({:gproc_ps_event, event, %{info: info}}, state) do
    case event do
      # info is a block
      :new_top_block ->
        spawn(fn ->
          Enum.each(info.txs, fn tx -> new_tx_mined(tx) end)
        end)
    end

    {:noreply, state}
  end
end
