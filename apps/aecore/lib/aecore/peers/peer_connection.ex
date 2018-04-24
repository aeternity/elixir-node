defmodule Aecore.Peers.PeerConnection do
  use GenServer

  alias Aecore.Structures.Block

  require Logger

  @behaviour :ranch_protocol

  @p2p_protocol_vsn 2
  @noise_timeout 5000

  def start_link(ref, socket, transport, opts) do
    args = [ref, socket, transport, opts]
    {:ok, :proc_lib.start_link(__MODULE__, :accept_init, args)}
  end

  def start_link(conn_info) do
    GenServer.start_link(__MODULE__, conn_info)
  end

  def accept_init(ref, socket, :ranch_tcp, opts) do
    :ok = :proc_lib.init_ack({:ok, self()})
    {:ok, {host, _port}} = :inet.peername(socket)
    host_bin = host |> :inet.ntoa() |> :binary.list_to_bin()
    genesis_hash = Block.genesis_hash()
    version = <<@p2p_protocol_vsn::64>>
    state =
      Map.merge(opts, %{role: :responder, host: host_bin, version: version, genesis: genesis_hash})

    noise_opts = noise_opts(state.seckey, state.pubkey, genesis_hash, version)
        :ok = :ranch.accept_ack(ref)
    :ok = :ranch_tcp.setopts(socket, [{:active, true}])
    case :enoise.accept(socket, noise_opts) do
      {:ok, noise_socket, new_state} ->
        :gen_server.enter_loop(__MODULE__, [], [])

      {:error, reason} ->
        Logger.error(reason)
        :ranch_tcp.close(socket)
    end
  end

  def init(conn_info) do
    genesis_hash = Block.genesis_hash()

    updated_con_info =
      Map.merge(conn_info, %{
        role: :initiator,
        version: <<@p2p_protocol_vsn::64>>,
        genesis: genesis_hash
      })

    # trigger a timeout so that we can attempt to connect immediately
    {:ok, updated_con_info, 0}
  end

  def handle_info(:timeout, %{host: host, port: port} = state) do
    case :gen_tcp.connect(host, port, [:binary, reuseaddr: true, active: false]) do
      {:ok, socket} ->
        :gen_tcp.controlling_process(socket, self())
        noise_opts =
          noise_opts(state.seckey, state.pubkey, state.r_pubkey, state.genesis, state.version)

        :inet.setopts(socket, active: true)

        case :enoise.connect(socket, noise_opts) do
          {:ok, noise_socket, s} ->
            {:noreply, noise_socket}

          {:error, reason} ->
            Logger.error(reason)
            :gen_tcp.close(socket)
            {:stop, :normal, state}
        end

      {:error, reason} ->
        Logger.error(reason)
        {:stop, :normal, state}
    end
  end

  def handle_info({:noise, _, <<type::16, payload::binary>>}, _from, state) do
    {:noreply, state}
  end

  def handle_call({:send, msg}, _from, %{status: {:connected, socket}} = state) do
    :enoise.send(socket, msg)
    {:reply, :ok, state}
  end

  def noise_opts(seckey, pubkey, r_pubkey, genesis_hash, version) do
    [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, seckey, pubkey),
      rs: :enoise_keypair.new(:dh25519, r_pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
  end

  def noise_opts(seckey, pubkey, genesis_hash, version) do
    [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, seckey, pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
  end
end
