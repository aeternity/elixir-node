defmodule Aecore.Peers.PeerConnection do
  @moduledoc """
  One instance of this handles a single connection to a peer.
  """

  use GenServer

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Worker.Supervisor
  alias Aecore.Peers.Sync
  alias Aecore.Peers.Jobs
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.SignedTx

  require Logger

  @behaviour :ranch_protocol

  @p2p_protocol_vsn 2
  @p2p_msg_version 1
  @noise_timeout 5000

  @msg_fragment 0
  @p2p_response 100
  @ping 1
  @get_header_by_hash 3
  @get_header_by_height 15
  @header 4
  @get_n_successors 5
  @header_hashes 6
  @get_block 7
  @block 11
  @tx 9
  @get_mempool 13
  @mempool 14

  @max_packet_size 0x1FF
  @fragment_size 0x1F9
  @fragment_size_bits @fragment_size * 8
  @msg_id_size 2

  @peer_share_count 32

  @first_ping_timeout 30_000

  def start_link(ref, socket, transport, opts) do
    args = [ref, socket, transport, opts]
    {:ok, pid} = :proc_lib.start_link(__MODULE__, :accept_init, args)
    {:ok, pid}
  end

  def start_link(conn_info) do
    GenServer.start_link(__MODULE__, conn_info)
  end

  def accept_init(ref, socket, :ranch_tcp, opts) do
    :ok = :proc_lib.init_ack({:ok, self()})
    {:ok, {host, _}} = :inet.peername(socket)
    host_bin = host |> :inet.ntoa() |> :binary.list_to_bin()
    genesis_hash = Block.genesis_hash()
    version = <<@p2p_protocol_vsn::64>>

    state = Map.merge(opts, %{host: host_bin, version: version, genesis: genesis_hash})

    noise_opts = noise_opts(state.privkey, state.pubkey, genesis_hash, version)
    :ok = :ranch.accept_ack(ref)
    :ok = :ranch_tcp.setopts(socket, [{:active, true}])

    case :enoise.accept(socket, noise_opts) do
      {:ok, noise_socket, noise_state} ->
        r_pubkey = noise_state |> :enoise_hs_state.remote_keys() |> :enoise_keypair.pubkey()
        new_state = Map.merge(state, %{r_pubkey: r_pubkey, status: {:connected, noise_socket}})
        Process.send_after(self(), :first_ping_timeout, @first_ping_timeout)
        :gen_server.enter_loop(__MODULE__, [], new_state)

      {:error, _reason} ->
        :ranch_tcp.close(socket)
    end
  end

  def init(conn_info) do
    genesis_hash = Block.genesis_hash()

    updated_con_info =
      Map.merge(conn_info, %{
        version: <<@p2p_protocol_vsn::64>>,
        genesis: genesis_hash
      })

    # trigger a timeout so that a connection is attempted immediately
    {:ok, updated_con_info, 0}
  end

  @spec ping(pid()) :: :ok | :error
  def ping(pid) when is_pid(pid) do
    GenServer.call(pid, :ping)
  end

  @spec get_header_by_hash(binary(), pid()) :: {:ok, Header.t()} | {:error, term()}
  def get_header_by_hash(hash, pid) when is_pid(pid) do
    @get_header_by_hash
    |> pack_msg(%{hash: hash})
    |> send_request_msg(pid)
  end

  @spec get_header_by_height(non_neg_integer(), pid()) :: {:ok, Header.t()} | {:error, term()}
  def get_header_by_height(height, pid) when is_pid(pid) do
    @get_header_by_height
    |> pack_msg(%{height: height})
    |> send_request_msg(pid)
  end

  @spec get_n_successors(binary(), non_neg_integer(), pid()) ::
          {:ok, list(Header.t())} | {:error, term()}
  def get_n_successors(hash, n, pid) when is_pid(pid) do
    @get_n_successors
    |> pack_msg(%{hash: hash, n: n})
    |> send_request_msg(pid)
  end

  @spec get_block(binary(), pid()) :: {:ok, Block.t()} | {:error, term()}
  def get_block(hash, pid) when is_pid(pid) do
    @get_block
    |> pack_msg(%{hash: hash})
    |> send_request_msg(pid)
  end

  @spec get_mempool(pid()) :: {:ok, list(SignedTx.t())}
  def get_mempool(pid) when is_pid(pid) do
    @get_mempool
    |> pack_msg(<<>>)
    |> send_request_msg(pid)
  end

  @spec send_new_block(Block.t(), pid()) :: :ok | :error
  def send_new_block(block, pid) when is_pid(pid) do
    @block
    |> pack_msg(block)
    |> send_msg_no_response(pid)
  end

  @spec send_new_tx(SignedTx.t(), pid()) :: :ok | :error
  def send_new_tx(tx, pid) when is_pid(pid) do
    @tx
    |> pack_msg(tx)
    |> send_msg_no_response(pid)
  end

  def handle_call(:ping, _from, state) do
    :ok = do_ping(state)
    {:reply, :ok, state}
  end

  def handle_call(
        {:send_request_msg, <<type::16, _::binary>> = msg},
        from,
        %{status: {:connected, socket}} = state
      ) do
    :ok = :enoise.send(socket, msg)

    response_type =
      case type do
        @get_header_by_hash ->
          @header

        @get_header_by_height ->
          @header

        @get_n_successors ->
          @header_hashes

        @get_block ->
          @block

        @get_mempool ->
          @mempool
      end

    updated_state = Map.put(state, :requests, %{response_type => from})
    {:noreply, updated_state}
  end

  def handle_call({:send_msg_no_response, msg}, _from, %{status: {:connected, socket}} = state) do
    res = :enoise.send(socket, msg)
    {:reply, res, state}
  end

  def handle_call({:clear_request, type}, _from, state) do
    updated_state = state |> pop_in([:requests, type]) |> elem(1)
    {:reply, :ok, updated_state}
  end

  def handle_info(
        :first_ping_timeout,
        %{r_pubkey: r_pubkey, status: {:connected, socket}} = state
      ) do
    case Peers.have_peer?(r_pubkey) do
      true ->
        {:noreply, state}

      false ->
        :enoise.close(socket)
        {:stop, :normal, state}
    end
  end

  def handle_info(
        :timeout,
        %{
          genesis: genesis,
          version: version,
          pubkey: pubkey,
          privkey: privkey,
          r_pubkey: r_pubkey,
          host: host,
          port: port
        } = state
      ) do
    case :gen_tcp.connect(host, port, [:binary, reuseaddr: true, active: false]) do
      {:ok, socket} ->
        noise_opts = noise_opts(privkey, pubkey, r_pubkey, genesis, version)

        :inet.setopts(socket, active: true)

        case :enoise.connect(socket, noise_opts) do
          {:ok, noise_socket, _status} ->
            new_state = Map.put(state, :status, {:connected, noise_socket})
            peer = %{host: host, pubkey: r_pubkey, port: port, connection: self()}
            :ok = do_ping(new_state)
            Peers.add_peer(peer)
            {:noreply, new_state}

          {:error, reason} ->
            Logger.debug(fn -> ":enoise.connect ERROR: #{inspect(reason)}" end)
            :gen_tcp.close(socket)
            {:stop, :normal, state}
        end

      {:error, reason} ->
        Logger.debug(fn -> ":get_tcp.connect ERROR: #{inspect(reason)}" end)
        {:stop, :normal, state}
    end
  end

  def handle_info(
        {:noise, _,
         <<@msg_fragment::16, fragment_index::16, total_fragments::16, fragment::binary()>>},
        state
      ) do
    handle_fragment(state, fragment_index, total_fragments, fragment)
  end

  def handle_info({:noise, _, <<type::16, payload::binary()>>}, state) do
    deserialized_payload = rlp_decode(type, payload)
    self = self()

    case type do
      @p2p_response ->
        spawn(fn ->
          handle_response(deserialized_payload, self, Map.get(state, :requests, :empty))
        end)

      @ping ->
        spawn(fn -> handle_ping(deserialized_payload, self, state) end)

      @get_header_by_hash ->
        spawn(fn -> handle_get_header_by_hash(deserialized_payload, self) end)

      @get_header_by_height ->
        spawn(fn -> handle_get_header_by_height(deserialized_payload, self) end)

      @get_n_successors ->
        spawn(fn -> handle_get_n_successors(deserialized_payload, self) end)

      @get_block ->
        spawn(fn -> handle_get_block(deserialized_payload, self) end)

      @get_mempool ->
        spawn(fn -> handle_get_mempool(self) end)

      @block ->
        spawn(fn -> handle_new_block(deserialized_payload) end)

      @tx ->
        spawn(fn -> handle_new_tx(deserialized_payload) end)
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    Logger.info("Connection interrupted by peer - #{inspect(state)}")

    Peers.remove_peer(state.r_pubkey)
    {:stop, :normal, state}
  end

  defp do_ping(%{status: {:connected, socket}}) do
    ping_object = local_ping_object()
    serialized_ping_object = rlp_encode(@ping, ping_object)
    msg = <<@ping::16, serialized_ping_object::binary()>>
    :enoise.send(socket, msg)
  end

  defp send_response(result, type, pid) do
    payload =
      case result do
        {:ok, object} ->
          %{result: true, type: type, reason: nil, object: object}

        {:error, reason} ->
          %{result: false, type: type, reason: reason, object: nil}
      end

    @p2p_response
    |> pack_msg(payload)
    |> send_msg_no_response(pid)
  end

  defp send_request_msg(msg, pid), do: GenServer.call(pid, {:send_request_msg, msg})

  defp send_msg_no_response(msg, pid) when byte_size(msg) > @max_packet_size - @msg_id_size do
    number_of_chunks = msg |> byte_size() |> Kernel./(@fragment_size) |> Float.ceil() |> trunc()
    send_chunks(pid, 1, number_of_chunks, msg)
  end

  defp send_msg_no_response(msg, pid), do: GenServer.call(pid, {:send_msg_no_response, msg})

  defp send_chunks(pid, fragment_index, total_fragments, msg)
       when fragment_index == total_fragments do
    send_fragment(
      <<@msg_fragment::16, fragment_index::16, total_fragments::16, msg::binary()>>,
      pid
    )
  end

  defp send_chunks(
         pid,
         fragment_index,
         total_fragments,
         <<chunk::@fragment_size_bits, rest::binary()>>
       ) do
    send_fragment(
      <<@msg_fragment::16, fragment_index::16, total_fragments::16, chunk::@fragment_size_bits>>,
      pid
    )

    send_chunks(pid, fragment_index + 1, total_fragments, rest)
  end

  defp send_fragment(fragment, pid), do: GenServer.call(pid, {:send_msg_no_response, fragment})

  defp pack_msg(type, payload), do: <<type::16, rlp_encode(type, payload)::binary>>

  defp handle_fragment(state, 1, _m, fragment) do
    {:noreply, Map.put(state, :fragments, [fragment])}
  end

  defp handle_fragment(%{fragments: fragments} = state, fragment_index, total_fragments, fragment)
       when fragment_index == total_fragments do
    msg = [fragment | fragments] |> Enum.reverse() |> :erlang.list_to_binary()
    send(self(), {:noise, :unused, msg})
    {:noreply, Map.delete(state, :fragments)}
  end

  defp handle_fragment(%{fragments: fragments} = state, fragment_index, _m, fragment)
       when fragment_index == length(fragments) + 1 do
    {:noreply, %{state | fragments: [fragment | fragments]}}
  end

  defp handle_ping(payload, conn_pid, %{host: host, r_pubkey: r_pubkey}) do
    %{
      peers: peers,
      port: port
    } = payload

    if !Peers.have_peer?(r_pubkey) do
      peer = %{pubkey: r_pubkey, port: port, host: host, connection: conn_pid}
      Peers.add_peer(peer)
    end

    handle_ping_msg(payload, conn_pid)

    exclude = Enum.map(peers, fn peer -> peer.pubkey end)
    response_ping = local_ping_object(exclude)

    send_response({:ok, response_ping}, @ping, conn_pid)
  end

  defp handle_ping_msg(
         %{
           genesis_hash: genesis_hash,
           best_hash: best_hash,
           difficulty: difficulty,
           peers: peers
         },
         conn_pid
       ) do
    if Block.genesis_hash() == genesis_hash do
      cond do
        best_hash == Chain.top_block_hash() ->
          # don't sync - same top block
          :ok

        Chain.total_difficulty() > difficulty ->
          # don't sync - our difficulty is higher
          :ok

        true ->
          Sync.start_sync(conn_pid, best_hash)
          :ok
      end

      Enum.each(peers, fn peer ->
        if !Peers.have_peer?(peer.pubkey) do
          Peers.try_connect(peer)
        end
      end)

      Sync.fetch_mempool(conn_pid)
      Jobs.dequeue(:sync_jobs)
    else
      Logger.info("Genesis hash mismatch")
    end
  end

  defp handle_response(payload, parent, requests) do
    result = payload.result
    type = payload.type

    if type == @ping do
      handle_ping_msg(payload.object, parent)
    else
      reply =
        case result do
          true ->
            {:ok, payload.object}

          false ->
            {:error, payload.reason}
        end

      GenServer.reply(requests[type], reply)

      clear_request(parent, type)
    end
  end

  defp clear_request(pid, type) do
    GenServer.call(pid, {:clear_request, type})
  end

  defp handle_get_header_by_hash(payload, pid) do
    hash = payload.hash
    result = Chain.get_header_by_hash(hash)
    send_response(result, @header, pid)
  end

  defp handle_get_header_by_height(payload, pid) do
    height = payload.height
    result = Chain.get_header_by_height(height)
    send_response(result, @header, pid)
  end

  defp handle_get_n_successors(payload, pid) do
    starting_header = payload.hash
    count = payload.n

    result =
      case Chain.get_headers_forward(starting_header, count) do
        {:ok, headers} ->
          header_hashes =
            Enum.map(headers, fn header ->
              {header.height, BlockValidation.block_header_hash(header)}
              <<header.height::64, BlockValidation.block_header_hash(header)::binary>>
            end)

          {:ok, Enum.reverse(header_hashes)}

        {:error, reason} ->
          {:error, reason}
      end

    send_response(result, @header_hashes, pid)
  end

  defp handle_get_block(payload, pid) do
    hash = payload.hash
    result = Chain.get_block(hash)
    send_response(result, @block, pid)
  end

  defp handle_get_mempool(pid) do
    txs = Map.values(Pool.get_pool())
    send_response({:ok, %{txs: txs}}, @mempool, pid)
  end

  defp handle_new_block(payload) do
    block = payload.block
    Chain.add_block(block)
  end

  defp handle_new_tx(payload) do
    tx = payload.tx
    Pool.add_transaction(tx)
  end

  defp local_ping_object do
    peers = Peers.get_random(@peer_share_count)

    ping_object(peers)
  end

  defp local_ping_object(exclude) do
    peers = Peers.get_random(@peer_share_count, exclude)

    ping_object(peers)
  end

  defp ping_object(peers) do
    %{
      share: 32,
      genesis_hash: Block.genesis_hash(),
      best_hash: Chain.top_block_hash(),
      difficulty: Chain.total_difficulty(),
      peers: peers,
      port: Supervisor.sync_port()
    }
  end

  defp noise_opts(privkey, pubkey, r_pubkey, genesis_hash, version) do
    [
      {:rs, :enoise_keypair.new(:dh25519, r_pubkey)}
      | noise_opts(privkey, pubkey, genesis_hash, version)
    ]
  end

  defp noise_opts(privkey, pubkey, genesis_hash, version) do
    [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, privkey, pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
  end

  # RLP for peer messages

  # fragments aren't encoded
  def rlp_encode(@msg_fragment, fragment) do
    fragment
  end

  def rlp_encode(@p2p_response, %{result: result, type: type, object: object, reason: reason}) do
    serialized_result = bool_bin(result)

    serialized_reason = to_string(reason)

    serialized_object =
      case object do
        nil ->
          <<>>

        object ->
          rlp_encode(type, object)
      end

    ExRLP.encode([
      :binary.encode_unsigned(@p2p_msg_version),
      serialized_result,
      type,
      serialized_reason,
      serialized_object
    ])
  end

  def rlp_encode(@ping, %{
        share: share,
        genesis_hash: genesis_hash,
        best_hash: best_hash,
        difficulty: difficulty,
        peers: peers,
        port: port
      }) do
    ExRLP.encode([
      :binary.encode_unsigned(@p2p_msg_version),
      :binary.encode_unsigned(port),
      :binary.encode_unsigned(share),
      genesis_hash,
      :erlang.float_to_binary(difficulty),
      best_hash,
      Peers.rlp_encode_peers(peers)
    ])
  end

  def rlp_encode(@get_header_by_hash, %{hash: hash}) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), hash])
  end

  def rlp_encode(@get_header_by_height, %{height: height}) do
    ExRLP.encode([
      :binary.encode_unsigned(@p2p_msg_version),
      :binary.encode_unsigned(height)
    ])
  end

  def rlp_encode(@header, header) do
    header_binary = Header.encode_to_binary(header)
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), header_binary])
  end

  def rlp_encode(@get_n_successors, %{
        hash: hash,
        n: n
      }) do
    ExRLP.encode([
      :binary.encode_unsigned(@p2p_msg_version),
      hash,
      :binary.encode_unsigned(n)
    ])
  end

  def rlp_encode(@header_hashes, header_hashes) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), header_hashes])
  end

  def rlp_encode(@get_block, %{hash: hash}) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), hash])
  end

  def rlp_encode(@block, block) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), Block.rlp_encode(block)])
  end

  def rlp_encode(@tx, tx) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), SignedTx.rlp_encode(tx)])
  end

  def rlp_encode(@get_mempool, _data) do
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version)])
  end

  def rlp_encode(@mempool, %{txs: txs}) do
    encoded_txs = Enum.map(txs, fn tx -> SignedTx.rlp_encode(tx) end)
    ExRLP.encode([:binary.encode_unsigned(@p2p_msg_version), encoded_txs])
  end

  def rlp_decode(@msg_fragment, fragment) do
    fragment
  end

  def rlp_decode(@p2p_response, encoded_response) do
    # vsn should be addititonaly decoded with :binary.decode_unsigned
    [_vsn, result, type, reason, object] = ExRLP.decode(encoded_response)
    deserialized_result = bool_bin(result)

    deserialized_type = :binary.decode_unsigned(type)

    deserialized_reason =
      case reason do
        <<>> ->
          nil

        reason ->
          reason
      end

    deserialized_object =
      case object do
        <<>> ->
          nil

        object ->
          rlp_decode(deserialized_type, object)
      end

    %{
      result: deserialized_result,
      type: deserialized_type,
      reason: deserialized_reason,
      object: deserialized_object
    }
  end

  def rlp_decode(@ping, encoded_ping) do
    [
      # vsn should be addititonaly decoded with :binary.decode_unsigned
      _vsn,
      port,
      share,
      genesis_hash,
      difficulty,
      best_hash,
      peers
    ] = ExRLP.decode(encoded_ping)

    %{
      port: :binary.decode_unsigned(port),
      share: :binary.decode_unsigned(share),
      genesis_hash: genesis_hash,
      difficulty: :erlang.binary_to_float(difficulty),
      best_hash: best_hash,
      peers: Peers.rlp_decode_peers(peers)
    }
  end

  def rlp_decode(@get_header_by_hash, encoded_get_header_by_hash) do
    # vsn should be addititonaly decoded with :binary.decode_unsigned
    [_vsn, hash] = ExRLP.decode(encoded_get_header_by_hash)
    %{hash: hash}
  end

  def rlp_decode(@get_header_by_height, encoded_get_header_by_height) do
    # vsn should be addititonaly decoded with :binary.decode_unsigned
    [_vsn, height] = ExRLP.decode(encoded_get_header_by_height)
    %{height: :binary.decode_unsigned(height)}
  end

  def rlp_decode(@header, encoded_header) do
    [
      # vsn should be addititonaly decoded with :binary.decode_unsigned
      _vsn,
      header_binary
    ] = ExRLP.decode(encoded_header)

    {:ok, deserialized_header} = Header.decode_from_binary(header_binary)
    %{header: deserialized_header}
  end

  def rlp_decode(@get_n_successors, encoded_get_n_successors) do
    [
      # vsn should be addititonaly decoded with :binary.decode_unsigned
      _vsn,
      hash,
      n
    ] = ExRLP.decode(encoded_get_n_successors)

    %{
      hash: hash,
      n: :binary.decode_unsigned(n)
    }
  end

  def rlp_decode(@header_hashes, encoded_header_hashes) do
    [
      _vsn,
      header_hashes
    ] = ExRLP.decode(encoded_header_hashes)

    deserialized_hashes =
      Enum.map(header_hashes, fn <<height::64, hash::binary>> -> %{height: height, hash: hash} end)

    %{hashes: deserialized_hashes}
  end

  def rlp_decode(@get_block, encoded_block_hash) do
    [
      _vsn,
      block_hash
    ] = ExRLP.decode(encoded_block_hash)

    %{hash: block_hash}
  end

  def rlp_decode(@block, encoded_block) do
    [
      _vsn,
      block
    ] = ExRLP.decode(encoded_block)

    {:ok, deserialized_block} = Block.rlp_decode(block)
    %{block: deserialized_block}
  end

  def rlp_decode(@tx, encoded_tx) do
    [
      _vsn,
      tx
    ] = ExRLP.decode(encoded_tx)

    {:ok, deserialized_tx} = SignedTx.rlp_decode(tx)
    %{tx: deserialized_tx}
  end

  def rlp_decode(@get_mempool, _data) do
    []
  end

  def rlp_decode(@mempool, encoded_pool) do
    [_vsn, pool] = ExRLP.decode(encoded_pool)

    txs =
      Enum.map(pool, fn encoded_tx ->
        {:ok, tx} = SignedTx.rlp_decode(encoded_tx)
        tx
      end)

    %{txs: txs}
  end

  defp bool_bin(bool) do
    case bool do
      true ->
        <<1>>

      false ->
        <<0>>

      <<1>> ->
        true

      <<0>> ->
        false
    end
  end
end
