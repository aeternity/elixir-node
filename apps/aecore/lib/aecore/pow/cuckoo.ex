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

  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Structures.Header
  alias Aecore.Pow.Hashcash

  @doc """
  Proof of Work verification (with difficulty check)
  """
  @spec verify(map()) :: boolean()
  def verify(%Header{difficulty_target: difficulty,
                     pow_evidence: soln}=header) do
    case test_target(soln, difficulty) do
      true  -> process(:verify, header)
      false -> false
    end
  end

  @doc """
  Find a nonce
  """
  @spec generate(map()) :: {:ok, map()}
  def generate(%{}=header), do: process(:generate, header)

  ###=============================================================================
  ### Internal functions
  ###=============================================================================
  defp process(process, header) do
    with {:ok, builder} <- hash_header(builder(process, header)),
         {:ok, builder} <- get_os_cmd(builder),
         {:ok, builder} <- exec_os_cmd(builder),
         {:ok, builder} <- build_response(builder)
      do
      {:ok, %{process: process}=builder}
      case process do
        :generate -> builder.header
        :verify -> builder.verified
      end

      else
        {:error, %{error: :no_solution}} ->
          {:error, :no_solution}
        {:error, %{error: reason}} ->
          {:error, reason}
    end
  end

  defp hash_header(%{header: header}=builder) do
    header = %{header | pow_evidence: nil}
    hash   = :base64.encode_to_string(BlockValidation.block_header_hash(header))
    {:ok, %{builder | hash: hash}}
  end

  defp get_os_cmd(%{process: process,
                    header: header,
                    hash: hash}=builder) do
    {:ok, command, options} = build_command(process, header.nonce, hash)
    {:ok, %{builder | cmd: command, cmd_opt: options}}
  end

  defp build_command(process, nonce, hash) do
    {exe, _extra, size} = Application.get_env(:aecore, :pow)[:params]
    cmd =
      case process do
        :generate -> [exe, size, " -h ", hash," -n ", nonce]
        :verify ->   ["./verify", size, " -h ", hash, " -n ", nonce]
      end
    command = Enum.join(export_ld_lib_path() ++ cmd)
    options = command_options(process)
    {:ok, command, options}
  end

  defp command_options(:verify), do: default_command_options() ++ [{:stdin, true}]
  defp command_options(:generate), do: default_command_options()

  defp default_command_options() do
    [{:stdout, self()},
     {:stderr, self()},
     {:kill_timeout, 0},
     {:sync, false},
     {:cd, Application.get_env(:aecore, :pow)[:bin_dir]},
     {:env, [{"SHELL", "/bin/sh"}]},
     {:monitor, true}]
  end

  defp exec_os_cmd(%{process: process,
                     header: header,
                     cmd: command,
                     cmd_opt: options}=builder) do
    try do
      {:ok, _erlpid, ospid} = Exexec.run(command, options)
      if process == :verify do
        Exexec.send(ospid, solution_to_string(header.pow_evidence))
        Exexec.send(ospid, :eof)
      end

      res =
        case wait_for_result(process) do
          {:ok, response} -> {:ok, %{ builder | response: response}}
          {:error, reason} -> {:error, %{builder | error: reason}}
        end
      Exexec.stop(ospid)
      res
    catch
      error -> {:error, %{builder | error: error} }
    end
  end

  defp export_ld_lib_path() do
    ldpathvar = case :os.type() do
                  {:unix, :darwin} -> "DYLD_LIBRARY_PATH"
                  {:unix, _}       -> "LD_LIBRARY_PATH"
                end
    ["export ", ldpathvar, "=../lib:$", ldpathvar, "; "]
  end

  ## Consider buffer
  defp wait_for_result(process) do
    receive do
      {:stdout, _os_pid, msg} ->
        handle_raw_data(process, msg)
      {:stderr, _os_pid, msg} ->
        Logger.error("[Cuckoo] stderr: #{inspect(msg)}")
        {:error, :miner_was_stopped}
      {:DOWN, _ref, :process, _pid, :killed} ->
        exit(:normal)
      {:EXIT, _pid, :shutdown} ->
        exit(:shutdown)
      {:DOWN, _, :process, _pid, :normal} ->
        wait_for_result(process)
      any ->
        Logger.error("[Cuckoo] wait_for_response any case : #{inspect(any)}")
        {:error, :no_value}
    end
  end

  defp handle_raw_data(:verify, msg) do
    {:ok, {:verified, length(String.split(msg, "Verified with cyclehash")) > 1}}
  end

  defp handle_raw_data(:generate, msg) do
    case String.split msg, "\nSolution " do
      [_, solution] ->
        [solution, _more | _] = String.split solution, "\n"
        solution =
        for e <- String.split(solution, " "), do: String.to_integer(Base.encode16(e))
        {:ok, {:generated, solution}}
      _ -> {:error, :no_solution}
    end
  end

  defp build_response(%{error: error}=builder) when error != nil do
    {:error, %{builder | error: error} }
  end

  defp build_response(%{header: header,
                        response: response}=builder) do
    case response do
      {:verified, verified} ->
        {:ok, %{ builder | verified: verified}}
      {:generated, soln} ->
        if test_target(soln, header.difficulty_target) do
          {:ok, %{ builder | header: %{header | pow_evidence: soln}}}
        else
          {:error, %{builder | error: :no_solution}}
        end
      {:error, error} ->
        Logger.error("[Cuckoo] buildig response: #{inspect(error)}")
        {:error, %{builder | error: error} }
    end
  end

  ## White paper, section 9: rather than adjusting the nodes/edges ratio, a
  ## hash-based difficulty is suggested: the sha256 hash of the cycle nonces
  ## is restricted to be under the difficulty value (0 < difficulty < 2^256)
  @spec test_target(soln :: list(), target :: integer()) :: true | false
  defp test_target(soln, target) do
    nodesize = get_node_size()
    bin = solution_to_binary(:lists.sort(soln), nodesize * 8, <<>>)
    Hashcash.generate(:cuckoo, bin, target)
  end


  ## The Cuckoo solution is a list of uint32 integers unless the graph size is
  ## greater than 33 (when it needs u64 to store). Hash result for difficulty
  ## control accordingly.
  @spec get_node_size() :: integer()
  defp get_node_size() do
    case Application.get_env(:aecore, :pow)[:params] do
      {_, _, size} when size > 32 -> 8
      {_, _, size} when size > 0 -> 4
    end
  end

  ## Convert solution (a list of 42 numbers) to a binary
  defp solution_to_binary([], _Bits, acc), do: acc
  defp solution_to_binary([h | t], bits, acc) do
    solution_to_binary(t, bits, acc <> <<h::size(bits) >>)
  end

  defp solution_to_string(soln) do
    list = for e <- soln, do: Base.decode16!(Integer.to_string e)
    Enum.join(list, " ")
  end

  defp builder(process, header) do
    %{:header         => header,
      :hash           => nil,
      :process        => process,
      :response       => nil,
      :verified       => false,
      :cmd            => nil,
      :cmd_opt        => nil,
      :error          => nil}
  end

end
