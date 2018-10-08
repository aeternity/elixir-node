defmodule Aecore.Pow.Cuckoo do
  @moduledoc """
  A library providing Cuckoo Cycle PoW generation and verification.
  John Tromp:  https://github.com/tromp/cuckoo
  White paper: https://github.com/tromp/cuckoo/blob/master/doc/cuckoo.pdf?raw=true

  Source file used for building this:
    - https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_pow_cuckoo.erl
    - https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_pow.erl
  """

  require Logger

  alias Aecore.Chain.Header
  alias Aecore.Pow.Hashcash
  alias Aeutil.Hash

  @behaviour Aecore.Pow.PowAlgorithm

  @type error() :: {:error, String.t()}

  @doc """
  Proof of Work verification (with difficulty check)
  """
  @spec verify(Header.t()) :: boolean()
  def verify(%Header{target: target, pow_evidence: soln} = header) do
    if test_target(soln, target) do
      {:ok, response} = process(:verify, header)
      response
    else
      false
    end
  end

  @doc """
  Find a nonce
  """
  @spec generate(Header.t()) :: {:ok, Header.t()} | error()
  def generate(%Header{} = header), do: process(:generate, header)

  defp process(process, header) do
    with {:ok, builder} <- hash_header(builder(process, header)),
         {:ok, builder} <- get_os_cmd(builder),
         {:ok, builder} <- exec_os_cmd(builder),
         {:ok, builder} <- build_response(builder) do
      {:ok, %{response: response} = builder}
      {:ok, response}
    else
      {:error, %{error: reason}} ->
        {:error, reason}
    end
  end

  defp hash_header(%{header: %Header{nonce: nonce} = header} = builder) do
    blake2b = Header.hash(%{header | nonce: 0, pow_evidence: :no_value})
    {:ok, %{builder | hash: pack_header_and_nonce(blake2b, nonce)}}
  end

  defp get_os_cmd(%{process: process, hash: hash} = builder) do
    {:ok, command, options} = build_command(process, hash)
    {:ok, %{builder | cmd: command, cmd_opt: options}}
  end

  defp build_command(process, hash) do
    {exe, _extra, size} = Application.get_env(:aecore, :pow)[:params]

    cmd =
      case process do
        :generate -> [exe, " -h ", hash]
        :verify -> ["./verify", size, " -h ", hash]
      end

    command = Enum.join(export_ld_lib_path() ++ cmd)
    options = command_options(process)
    {:ok, command, options}
  end

  defp command_options(:verify), do: [{:stdin, true} | default_command_options()]

  defp command_options(:generate), do: default_command_options()

  defp default_command_options do
    [
      {:stdout, self()},
      {:stderr, self()},
      {:kill_timeout, 0},
      {:sync, false},
      {:cd, Application.get_env(:aecore, :pow)[:bin_dir]},
      {:env, [{"SHELL", "/bin/sh"}]},
      {:monitor, true}
    ]
  end

  defp exec_os_cmd(
         %{
           process: process,
           header: %Header{pow_evidence: pow_evidence},
           cmd: command,
           cmd_opt: options
         } = builder
       ) do
    {:ok, _erlpid, ospid} = Exexec.run(command, options)

    if process == :verify do
      Exexec.send(ospid, solution_to_string(pow_evidence))
      Exexec.send(ospid, :eof)
    end

    res =
      case wait_for_result(process, "") do
        {:ok, response} -> {:ok, %{builder | response: response}}
        {:error, reason} -> {:error, %{builder | error: reason}}
      end

    Exexec.stop(ospid)
    res
  catch
    error -> {:error, %{builder | error: error}}
  end

  defp export_ld_lib_path do
    ldpathvar =
      case :os.type() do
        {:unix, :darwin} -> "DYLD_LIBRARY_PATH"
        {:unix, _} -> "LD_LIBRARY_PATH"
      end

    ["export ", ldpathvar, "=../lib:$", ldpathvar, "; "]
  end

  # Consider buffer
  defp wait_for_result(process, buff) do
    receive do
      {:stdout, _os_pid, msg} ->
        wait_for_result(process, msg <> buff)

      {:stderr, _os_pid, msg} ->
        Logger.error("#{__MODULE__}: stderr: #{inspect(msg)}")
        {:error, :miner_was_stopped}

      {:EXIT, _pid, :shutdown} ->
        exit(:shutdown)

      {:DOWN, _, :process, _pid, :normal} ->
        # Here we are supposed to have the whole data from the os port
        handle_raw_data(process, buff)

      any ->
        Logger.error("#{__MODULE__}: Unexpeted error : #{inspect(any)}")
        exit(:kill)
    end
  end

  defp handle_raw_data(:verify, msg) do
    {:ok, {:verified, length(String.split(msg, "Verified with cyclehash")) > 1}}
  end

  defp handle_raw_data(:generate, msg) do
    case String.split(msg, "\nSolution ") do
      [_, solution] ->
        [solution, _more | _] = String.split(solution, "\n")
        solution = for e <- String.split(solution, " "), do: e |> Integer.parse(16) |> elem(0)
        {:ok, {:generated, solution}}

      _ ->
        {:error, :no_solution}
    end
  end

  defp build_response(%{error: error} = builder) when error != nil do
    Logger.error("#{__MODULE__}: Unexpected error: #{inspect(error)}")
    {:error, %{builder | error: error}}
  end

  defp build_response(%{response: {:verified, verified}} = builder) do
    {:ok, %{builder | response: verified}}
  end

  defp build_response(
         %{header: %Header{target: target} = header, response: {:generated, soln}} = builder
       ) do
    if test_target(soln, target) do
      {:ok, %{builder | response: %{header | pow_evidence: soln}}}
    else
      {:error, %{builder | error: :no_solution}}
    end
  end

  # White paper, section 9: rather than adjusting the nodes/edges ratio, a
  # hash-based difficulty is suggested: the sha256 hash of the cycle nonces
  # is restricted to be under the difficulty value (0 < difficulty < 2^256)
  @spec test_target(list(), non_neg_integer()) :: boolean()
  defp test_target(soln, target) do
    nodesize = get_node_size()
    bin = solution_to_binary(:lists.sort(soln), nodesize * 8, <<>>)
    hash = Hash.hash(bin)
    Hashcash.verify(hash, target)
  end

  # The Cuckoo solution is a list of uint32 integers unless the graph size is
  # greater than 33 (when it needs u64 to store). Hash result for difficulty
  # control accordingly.
  @spec get_node_size() :: non_neg_integer()
  defp get_node_size do
    case Application.get_env(:aecore, :pow)[:params] do
      {_, _, size} when size > 32 -> 8
      {_, _, size} when size > 0 -> 4
    end
  end

  # Convert solution (a list of 42 numbers) to a binary
  defp solution_to_binary([], _Bits, acc), do: acc

  defp solution_to_binary([h | t], bits, acc) do
    solution_to_binary(t, bits, acc <> <<h::size(bits)>>)
  end

  defp solution_to_string(soln) do
    list = for e <- soln, do: e |> :binary.encode_unsigned() |> Base.encode16()
    Enum.join(list, " ")
  end

  @spec pack_header_and_nonce(binary(), integer()) :: charlist()
  defp pack_header_and_nonce(hash, nonce) do
    nonce_str = :base64.encode_to_string(<<nonce::unsigned-little-integer-size(64)>>)
    hash_str = :base64.encode_to_string(hash)
    hash_str ++ nonce_str
  end

  defp builder(process, %Header{} = header) do
    %{
      :header => header,
      :hash => nil,
      :process => process,
      :response => nil,
      :verified => false,
      :cmd => nil,
      :cmd_opt => nil,
      :error => nil
    }
  end
end
