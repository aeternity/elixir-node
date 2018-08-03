defmodule Aecore.Channel.Session do
  use GenServer

  alias Aecore.Peers.P2PUtils

  require Logger

  @behaviour :ranch_protocol
  @channel_open 1
  @channel_accept 2
  @channel_reestabl 3
  @channel_reest_ack 4
  @funding_created 5
  @funding_signed 6
  @funding_locked 7
  @update 8
  @update_ack 9
  @update_error 10
  @deposit_created 11
  @deposit_signed 12
  @deposit_locked 13
  @deposit_error 14
  @withdraw_created 15
  @withdraw_signed 16
  @withdraw_locked 17
  @withdraw_error 18
  @leave 94
  @leave_ack 95
  @inband_message 96
  @error 97
  @shutdown 98
  @shutdown_ack 99

  def start_link(ref, socket, transport, %{}) do
    args = [ref, socket, transport, %{}]
    {:ok, pid} = :proc_lib.start_link(__MODULE__, :accept_init, args)
    {:ok, pid}
  end

  def start_link(conn_info) do
    GenServer.start_link(__MODULE__, conn_info)
  end

  def init(conn_info) do
    # trigger a timeout so that a connection is attempted immediately
    {:ok, conn_info, 0}
  end

  def accept_init(ref, socket, :ranch_tcp, %{}) do
    :ok = :proc_lib.init_ack({:ok, self()})

    noise_opts = P2PUtils.noise_opts()
    :ok = :ranch.accept_ack(ref)
    :ok = :ranch_tcp.setopts(socket, [{:active, true}])

    case :enoise.accept(socket, noise_opts) do
      {:ok, noise_socket, _noise_state} ->
        new_state = %{connection: noise_socket}
        :gen_server.enter_loop(__MODULE__, [], new_state)

      {:error, _reason} ->
        :ranch_tcp.close(socket)
    end
  end

  def open_channel(
        channel_info,
        pid
      ) do
    @channel_open
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def accept_channel(
        channel_info,
        pid
      ) do
    @channel_accept
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def channel_reestablish(
        channel_info,
        pid
      ) do
    @channel_reestabl
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def channel_reestablish_ack(
        channel_info,
        pid
      ) do
    @channel_reest_ack
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def funding_created(channel_info, pid) do
    @funding_created
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def funding_signed(channel_info, pid) do
    @funding_signed
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def funding_lock(channel_info, pid) do
    @funding_locked
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def update(channel_info, pid) do
    @update
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def update_ack(channel_info, pid) do
    @update_ack
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def update_error(channel_info, pid) do
    @update_error
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def deposit_created(channel_info, pid) do
    @deposit_created
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def deposit_signed(channel_info, pid) do
    @deposit_signed
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def deposit_locked(channel_info, pid) do
    @deposit_locked
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def deposit_error(channel_info, pid) do
    @deposit_error
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def withdraw_created(channel_info, pid) do
    @withdraw_created
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def withdraw_signed(channel_info, pid) do
    @withdraw_signed
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def withdraw_locked(channel_info, pid) do
    @withdraw_locked
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def withdraw_error(channel_info, pid) do
    @withdraw_error
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def inband_message(channel_info, pid) do
    @inband_message
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def leave(channel_info, pid) do
    @leave
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def leave_ack(channel_info, pid) do
    @leave_ack
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def shutdown(channel_info, pid) do
    @shutdown
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def shutdown_ack(channel_info, pid) do
    @shutdown_ack
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def error(channel_info, pid) do
    @error
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def encode(@error, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@error::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@shutdown_ack, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@shutdown_ack::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@shutdown, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@shutdown::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@leave_ack, %{
        channel_id: channel_id
      }) do
    <<@leave_ack::8, channel_id::256>>
  end

  def encode(@leave, %{
        channel_id: channel_id
      }) do
    <<@leave::8, channel_id::256>>
  end

  def encode(@inband_message, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@inband_message::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@withdraw_error, %{
        channel_id: channel_id,
        round: round
      }) do
    <<@withdraw_error::8, channel_id::256, round::32>>
  end

  def encode(@withdraw_locked, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@withdraw_locked::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@withdraw_signed, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@withdraw_signed::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@withdraw_created, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@withdraw_created::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@deposit_error, %{
        channel_id: channel_id,
        round: round
      }) do
    <<@deposit_error::8, channel_id::256, round::32>>
  end

  def encode(@deposit_locked, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@deposit_locked::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@deposit_signed, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@deposit_signed::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@deposit_created, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@deposit_created::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@update_error, %{
        channel_id: channel_id,
        round: round
      }) do
    <<@update_error::8, channel_id::256, round::32>>
  end

  def encode(@update_ack, %{
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@update_ack::8, channel_id::256, length::16, data::binary>>
  end

  def encode(@update, %{
        temporary_channel_id: temporary_channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@update::8, temporary_channel_id::256, length::16, data::binary>>
  end

  def encode(@funding_locked, %{
        temporary_channel_id: temporary_channel_id,
        channel_id: channel_id
      }) do
    <<@funding_locked::8, temporary_channel_id::256, channel_id::256>>
  end

  def encode(@funding_signed, %{
        temporary_channel_id: temporary_channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@funding_signed::8, temporary_channel_id::256, length::16, data::binary>>
  end

  def encode(@funding_created, %{
        temporary_channel_id: temporary_channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@funding_created::8, temporary_channel_id::256, length::16, data::binary>>
  end

  def encode(@channel_reest_ack, %{
        chain_hash: chain_hash,
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)

    <<@channel_reest_ack::8, chain_hash::256, channel_id::256, length::16, data::binary>>
  end

  def encode(@channel_reestabl, %{
        chain_hash: chain_hash,
        channel_id: channel_id,
        data: data
      }) do
    length = byte_size(data)
    <<@channel_reestabl::8, chain_hash::256, channel_id::256, length::16, data::binary>>
  end

  def encode(@channel_open, %{
        chain_hash: chain_hash,
        channel_id: channel_id,
        lock_period: lock_period,
        push_amount: push_amount,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        channel_reserve: channel_reserve,
        initiator_pubkey: initiator_pubkey
      }) do
    <<@channel_open::8, chain_hash::256, channel_id::256, lock_period::16, push_amount::64,
      initiator_amount::64, responder_amount::64, channel_reserve::64, initiator_pubkey::256>>
  end

  def encode(@channel_accept, %{
        chain_hash: chain_hash,
        temporary_channel_id: temporary_channel_id,
        minimum_depth: minimum_depth,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        channel_reserve: channel_reserve,
        initiator_pubkey: initiator_pubkey
      }) do
    <<@channel_accept::8, chain_hash::256, temporary_channel_id::256, minimum_depth::32,
      initiator_amount::64, responder_amount::64, channel_reserve::64, initiator_pubkey::256>>
  end

  defp send_msg(msg, pid), do: GenServer.call(pid, {:send_msg, msg})

  def handle_call({:send_msg, msg}, _from, %{connection: socket} = state) do
    :ok = :enoise.send(socket, msg)
    {:noreply, state}
  end

  def handle_info(:timeout, %{host: host, port: port}) do
    case :gen_tcp.connect(host, port, [:binary, reuseaddr: true, active: true]) do
      {:ok, socket} ->
        noise_opts = P2PUtils.noise_opts()

        case :enoise.connect(socket, noise_opts) do
          {:ok, noise_socket, _status} ->
            new_state = %{connection: noise_socket}
            {:noreply, new_state}

          {:error, reason} ->
            Logger.debug(fn -> ":enoise.connect ERROR: #{inspect(reason)}" end)
            :gen_tcp.close(socket)
            {:stop, :normal, %{}}
        end

      {:error, reason} ->
        Logger.debug(fn -> ":get_tcp.connect ERROR: #{inspect(reason)}" end)
        {:stop, :normal, %{}}
    end
  end

  def handle_info({:noise, _, msg}, state) do
    IO.inspect(msg, limit: :infinity)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    Logger.info("Channel connection interrupted by peer - #{inspect(state)}")

    {:stop, :normal, state}
  end
end
