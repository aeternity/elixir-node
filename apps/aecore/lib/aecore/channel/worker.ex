defmodule Aecore.Channel.Worker do
  @moduledoc """
  Module for managing Channels
  """

  alias Aecore.Chain.Block
  alias Aecore.Channel.ChannelStatePeer
  alias Aecore.Channel.ChannelTransaction

  alias Aecore.Channel.Tx.{
    ChannelCloseMutalTx,
    ChannelCloseSoloTx,
    ChannelSlashTx,
    ChannelSettleTx,
    ChannelCreateTx
  }

  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.Events

  use GenServer

  require Logger

  @type role :: :initiator | :responder

  @typedoc """
  State is a map channel_id -> channel_peer_state
  """
  @type state :: %{binary() => ChannelStatePeer.t()}

  @type error :: {:error, String.t()}

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    Events.subscribe(:new_top_block)
    {:ok, %{}}
  end

  @doc """
  Notifies the channel manager about a new mined tx
  """
  # , ChannelWidhdrawTx, ChannelDepositTx]  do
  def new_tx_mined(%SignedTx{data: %DataTx{type: type}} = tx) when type in [ChannelCreateTx] do
    receive_confirmed_tx(tx)
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

  def new_tx_mined(%SignedTx{}) do
    # We don't care about this tx
    :ok
  end

  @doc """
  Imports channels from a ChannelStatePeer object. Useful for storage
  """
  @spec import_channel(ChannelStatePeer.t()) :: :ok | error()
  def import_channel(%ChannelStatePeer{channel_id: channel_id} = channel_state) do
    GenServer.call(__MODULE__, {:import_channel, channel_id, channel_state})
  end

  @doc """
  Imports a channel from an open tx. Assumes no transactions were made
  """
  @spec import_from_open(SignedTx.t(), role()) :: :ok | error()
  def import_from_open(%SignedTx{data: %DataTx{type: ChannelCreateTx}} = open_tx, role)
      when is_atom(role) do
    case ChannelStatePeer.from_open(open_tx, role) do
      {:ok, peer_state} ->
        import_channel(peer_state)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Imports channel from open tx and ChannelStateOffChain.
  """
  @spec import_from_signed_tx_list(
          list(SignedTx.t() | ChannelOffChainTx.t()),
          role()
        ) :: :ok | error()
  def import_from_signed_tx_list(
        mutually_signed_tx_list,
        role
      )
      when is_atom(role) do
    case ChannelStatePeer.from_signed_tx_list(mutually_signed_tx_list, role) do
      {:ok, peer_state} ->
        import_channel(peer_state)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Initializes a channel with a temporary ID. This has to be called for every channel by both :initiator and :responder.
  """
  @spec initialize(
          binary(),
          Keys.pubkey(),
          Keys.pubkey(),
          role(),
          non_neg_integer()
        ) :: :ok | error()
  def initialize(temporary_id, initiator_pubkey, responder_pubkey, role, channel_reserve)
      when is_binary(temporary_id) and is_atom(role) and is_integer(channel_reserve) do
    GenServer.call(
      __MODULE__,
      {:initialize, temporary_id, initiator_pubkey, responder_pubkey, role, channel_reserve}
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
          non_neg_integer(),
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, binary(), SignedTx.t()} | error()
  def open(temporary_id, initiator_amount, responder_amount, locktime, fee, nonce, priv_key)
      when is_binary(temporary_id) and is_integer(locktime) and is_integer(fee) and
             is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(
      __MODULE__,
      {:open, temporary_id, initiator_amount, responder_amount, locktime, fee, nonce, priv_key}
    )
  end

  @doc """
  Signs open transaction. Can only be called once per channel by :responder. Returns fully signed SignedTx and adds it to Pool.
  """
  @spec sign_open(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          SignedTx.t(),
          Keys.sign_priv_key()
        ) :: {:ok, binary(), SignedTx.t()} | error()
  def sign_open(
        temporary_id,
        initiator_amount,
        responder_amount,
        locktime,
        %SignedTx{} = open_tx,
        priv_key
      )
      when is_binary(temporary_id) and is_binary(priv_key) do
    GenServer.call(
      __MODULE__,
      {:sign_open, temporary_id, initiator_amount, responder_amount, locktime, open_tx, priv_key}
    )
  end

  @doc """
  Transfers amount to other peer in channel. Returns half-signed channel off-chain state. Can only be called on open channel.
  """
  @spec transfer(binary(), non_neg_integer(), Keys.sign_priv_key()) ::
          {:ok, ChannelStateOffChain.t()} | error()
  def transfer(channel_id, amount, priv_key)
      when is_binary(channel_id) and is_integer(amount) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:transfer, channel_id, amount, priv_key})
  end

  @doc """
  Handles received channel state. If it's half signed and validates: signs it and returns it.
  """
  @spec receive_half_signed_tx(ChannelTransaction.channel_tx(), Keys.sign_priv_key()) ::
          {:ok, ChannelTransaction.channel_tx()} | error()
  def receive_half_signed_tx(half_signed_tx, priv_key) when is_binary(priv_key) do
    GenServer.call(__MODULE__, {:receive_half_signed_tx, half_signed_tx, priv_key})
  end

  @doc """
  Handles incoming uncorfirmed fully signed onchain Tx or confirmed fully signed offchain Tx.
  """
  @spec receive_fully_signed_tx(ChannelTransaction.channel_tx()) :: :ok | error()
  def receive_fully_signed_tx(fully_signed_tx) do
    GenServer.call(__MODULE__, {:receive_fully_signed_tx, fully_signed_tx})
  end

  @doc """
  Handles mined and confirmed ChannelCreateTx, ChannelWidthdrawTx, ChannelDepositTx
  """
  def receive_confirmed_tx(confirmed_onchain_tx) do
    GenServer.call(__MODULE__, {:receive_confirmed_tx, confirmed_onchain_tx})
  end

  @doc """
  Creates channel close transaction. This also blocks any new transactions from happening on channel.
  """
  @spec close(
          binary(),
          {non_neg_integer(), non_neg_integer()},
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: {:ok, SignedTx.t()} | error()
  def close(channel_id, {_, _} = fees, nonce, priv_key)
      when is_binary(channel_id) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:close, channel_id, fees, nonce, priv_key})
  end

  @doc """
  Handles received half signed close tx. If it validates returns fully signed close tx and adds it to Pool.
  """
  @spec receive_close_tx(
          binary(),
          SignedTx.t(),
          {non_neg_integer(), non_neg_integer()},
          Keys.sign_priv_key()
        ) :: {:ok, SignedTx.t()} | error()
  def receive_close_tx(channel_id, %SignedTx{} = close_tx, {_, _} = fees, priv_key)
      when is_binary(channel_id) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:receive_close_tx, channel_id, close_tx, fees, priv_key})
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
  @spec solo_close(binary(), non_neg_integer(), non_neg_integer(), Keys.sign_priv_key()) ::
          :ok | error()
  def solo_close(channel_id, fee, nonce, priv_key)
      when is_binary(channel_id) and is_integer(fee) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:solo_close, channel_id, fee, nonce, priv_key})
  end

  @doc """
  Slashes channel. Creates slash Tx and adds it to the pool.
  """
  @spec slash(binary(), non_neg_integer(), non_neg_integer(), Keys.sign_priv_key()) ::
          :ok | error()
  def slash(channel_id, fee, nonce, priv_key)
      when is_binary(channel_id) and is_integer(fee) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:slash, channel_id, fee, nonce, priv_key})
  end

  @doc """
  Notifies channel manager about mined slash or solo close transaction. If channel Manager has newer state for corresponding channel it creates a slash transaction and add it to pool.
  """
  @spec slashed(
          SignedTx.t(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.sign_priv_key()
        ) :: :ok | error()
  def slashed(%SignedTx{} = slash_tx, fee, nonce, priv_key)
      when is_integer(fee) and is_integer(nonce) and is_binary(priv_key) do
    GenServer.call(__MODULE__, {:slashed, slash_tx, fee, nonce, priv_key})
  end

  @doc """
  Creates a settle transaction and adds it to the pool
  """
  @spec settle(binary(), non_neg_integer(), non_neg_integer(), Keys.sign_priv_key()) ::
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
  Notifies the channel manager about a mined settle tx.
  """
  @spec settled(SignedTx.t()) :: :ok | error()
  def settled(%SignedTx{} = settle_tx) do
    GenServer.call(__MODULE__, {:settled, settle_tx})
  end

  @doc """
  Returns a map of all ChannelStatePeer objects.
  """
  @spec get_all_channels :: %{binary() => ChannelStatePeer.t()}
  def get_all_channels do
    GenServer.call(__MODULE__, :get_all_channels)
  end

  @doc """
  Returns the channel peer state of a channel with the specified id.
  """
  @spec get_channel(binary()) :: {:ok, ChannelStatePeer.t()} | error()
  def get_channel(channel_id) when is_binary(channel_id) do
    GenServer.call(__MODULE__, {:get_channel, channel_id})
  end

  def handle_call({:import_channel, channel_id, channel_state}, _from, state) do
    {:reply, :ok, Map.put(state, channel_id, channel_state)}
  end

  def handle_call(
        {:initialize, temporary_id, initiator_pubkey, responder_pubkey, role, channel_reserve},
        _from,
        state
      ) do
    peer_state =
      ChannelStatePeer.initialize(
        temporary_id,
        initiator_pubkey,
        responder_pubkey,
        channel_reserve,
        role
      )

    {:reply, :ok, Map.put(state, temporary_id, peer_state)}
  end

  def handle_call(
        {:open, temporary_id, initiator_amount, responder_amount, locktime, fee, nonce, priv_key},
        _from,
        state
      ) do
    peer_state = Map.get(state, temporary_id)

    {:ok, new_peer_state, new_id, open_tx} =
      ChannelStatePeer.open(
        peer_state,
        initiator_amount,
        responder_amount,
        locktime,
        fee,
        nonce,
        priv_key
      )

    new_state =
      state
      |> Map.drop([temporary_id])
      |> Map.put(new_id, new_peer_state)

    {:reply, {:ok, new_id, open_tx}, new_state}
  end

  def handle_call(
        {:sign_open, temporary_id, initiator_amount, responder_amount, locktime, open_tx,
         priv_key},
        _from,
        state
      ) do
    peer_state = Map.get(state, temporary_id)

    with {:ok, new_peer_state, id, signed_open_tx} <-
           ChannelStatePeer.sign_open(
             peer_state,
             initiator_amount,
             responder_amount,
             locktime,
             open_tx,
             priv_key
           ),
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

  def handle_call({:transfer, id, amount, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    case ChannelStatePeer.transfer(peer_state, amount, priv_key) do
      {:ok, new_peer_state, offchain_state} ->
        {:reply, {:ok, offchain_state}, Map.put(state, id, new_peer_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:receive_half_signed_tx, half_signed_tx, priv_key},
        _from,
        state
      ) do
    channel_id = ChannelTransaction.unsigned_payload(half_signed_tx).channel_id
    peer_state = Map.get(state, channel_id)

    with {:ok, new_peer_state, fully_signed_tx} <-
           ChannelStatePeer.receive_half_signed_tx(peer_state, half_signed_tx, priv_key),
         :ok <- send_tx_to_pool_if_confirmation_is_required(fully_signed_tx) do
      {:reply, {:ok, fully_signed_tx}, Map.put(state, channel_id, new_peer_state)}
    else
      :error ->
        {:reply, {:error, "Pool error"}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:receive_fully_signed_tx, fully_signed_tx}, _from, state) do
    channel_id = ChannelTransaction.channel_id(fully_signed_tx)
    peer_state = Map.get(state, channel_id)

    with {:ok, new_peer_state} <-
           ChannelStatePeer.receive_fully_signed_tx(peer_state, fully_signed_tx) do
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    else
      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:receive_confirmed_tx, confirmed_onchain_tx}, _from, state) do
    channel_id = ChannelTransaction.channel_id(confirmed_onchain_tx)

    if Map.has_key?(state, channel_id) do
      peer_state = Map.get(state, channel_id)

      with {:ok, new_peer_state} <-
             ChannelStatePeer.receive_confirmed_tx(peer_state, confirmed_onchain_tx) do
        {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
      else
        {:error, _} = err ->
          {:reply, err, state}
      end
    else
      {:reply, {:error, "Channel ID not present"}, state}
    end
  end

  def handle_call({:close, id, fees, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    case ChannelStatePeer.close(peer_state, fees, nonce, priv_key) do
      {:ok, new_peer_state, close_tx} ->
        {:reply, {:ok, close_tx}, Map.put(state, id, new_peer_state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:receive_close_tx, id, close_tx, fees, priv_key}, _from, state) do
    peer_state = Map.get(state, id)

    with {:ok, new_peer_state, signed_close_tx} <-
           ChannelStatePeer.receive_close_tx(peer_state, close_tx, fees, priv_key),
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

  def handle_call({:closed, %SignedTx{data: %DataTx{payload: payload}}}, _from, state) do
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

  def handle_call({:slash, channel_id, fee, nonce, priv_key}, _from, state) do
    peer_state = Map.get(state, channel_id)

    with {:ok, new_peer_state, tx} <- ChannelStatePeer.slash(peer_state, fee, nonce, priv_key),
         :ok <- Pool.add_transaction(tx) do
      {:reply, :ok, Map.put(state, channel_id, new_peer_state)}
    else
      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, "#{__MODULE__}: Pool error"}
    end
  end

  def handle_call(
        {
          :slashed,
          %SignedTx{
            data: %DataTx{
              payload: payload
            }
          } = slash_tx,
          fee,
          nonce,
          priv_key
        },
        _from,
        state
      ) do
    channel_id =
      case payload do
        %ChannelCloseSoloTx{channel_id: channel_id} ->
          channel_id

        %ChannelSlashTx{channel_id: channel_id} ->
          channel_id
      end

    if Map.has_key?(state, channel_id) do
      peer_state = Map.get(state, channel_id)

      {:ok, new_peer_state, tx} =
        ChannelStatePeer.slashed(peer_state, slash_tx, fee, nonce, priv_key)

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

  def handle_call({:settled, %SignedTx{data: %DataTx{payload: payload}}}, _from, state) do
    %ChannelSettleTx{channel_id: channel_id} = payload

    if Map.has_key?(state, channel_id) do
      new_peer_state = state |> Map.get(channel_id) |> ChannelStatePeer.settled()
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

  # Calculates the most recent state hash for the given channel id
  def handle_call({:calculate_state_hash, channel_id}, _from, state) do
    dispatch_function_call_to_channel(state, channel_id, &ChannelStatePeer.calculate_state_hash/1)
  end

  # Retrieves the most recent chainstate for the given channel id
  def handle_call({:most_recent_chainstate, channel_id}, _from, state) do
    dispatch_function_call_to_channel(
      state,
      channel_id,
      &ChannelStatePeer.most_recent_chainstate/1
    )
  end

  # Retrieves the sequence of the highest offchain chainstate for the given channel id
  def handle_call({:sequence, channel_id}, _from, state) do
    dispatch_function_call_to_channel(state, channel_id, &ChannelStatePeer.sequence/1)
  end

  # Retrieves the amount of funds belonging to our account according to the most recent chainstate for the given channel id
  def handle_call({:our_offchain_account_balance, channel_id}, _from, state) do
    dispatch_function_call_to_channel(
      state,
      channel_id,
      &ChannelStatePeer.our_offchain_account_balance/1
    )
  end

  # Retrieves the amount of funds belonging to the other peer according to the most recent chainstate for the given channel id
  def handle_call({:foreign_offchain_account_balance, channel_id}, _from, state) do
    dispatch_function_call_to_channel(
      state,
      channel_id,
      &ChannelStatePeer.foreign_offchain_account_balance/1
    )
  end

  # Safely invokes the given function for the given channel id
  @spec dispatch_function_call_to_channel(state(), binary(), function()) ::
          {:reply, error() | {:ok, any()}, state()}
  defp dispatch_function_call_to_channel(state, channel_id, fun) when is_function(fun, 1) do
    if Map.has_key?(state, channel_id) do
      {:reply, {:ok, fun.(Map.get(state, channel_id))}, state}
    else
      {:reply, {:error, "#{__MODULE__}: No such channel"}, state}
    end
  end

  @spec send_tx_to_pool_if_confirmation_is_required(ChannelTransaction.signed_tx()) ::
          :ok | :error
  defp send_tx_to_pool_if_confirmation_is_required(tx) do
    if ChannelTransaction.requires_onchain_confirmation?(tx) do
      Pool.add_transaction(tx)
    else
      :ok
    end
  end

  def handle_info({:gproc_ps_event, event, %{info: %Block{txs: txs}}}, state) do
    case event do
      # info is a block
      :new_top_block ->
        spawn(fn ->
          Enum.each(txs, fn tx -> new_tx_mined(tx) end)
        end)
    end

    {:noreply, state}
  end
end
