defmodule Aecore.Channel.Session do
  use GenServer

  alias Aecore.Peers.P2PUtils

  require Logger

  @behaviour :ranch_protocol

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
    1
    |> encode(channel_info)
    |> send_msg(pid)
  end

  def encode(1, %{
        chain_hash: chain_hash,
        channel_id: channel_id,
        lock_period: lock_period,
        push_amount: push_amount,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        channel_reserve: channel_reserve,
        initiator_pubkey: initiator_pubkey
      }) do
    <<1::8, chain_hash::256, channel_id::256, lock_period::16, push_amount::64, initiator_amount::64,
      responder_amount::64, channel_reserve::64, initiator_pubkey::256>>
  end

  defp send_msg(msg, pid) do
          IO.inspect(msg, limit: :infinity)
    GenServer.call(pid, {:send_msg, msg})
  end
  def handle_call({:send_msg,msg},_from,%{connection: socket} = state) do
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

  def handle_info({:noise,_,msg}, state) do
    IO.inspect(msg,limit: :infinity)
    {:noreply,state}
  end

  def handle_info({:tcp_closed, _}, state) do
    Logger.info("Channel connection interrupted by peer - #{inspect(state)}")

    {:stop, :normal, state}
  end
end
