defmodule Aecore.Pow.Cuckoo do
  @moduledoc """
  A library providing Cuckoo Cycle PoW generation and verification.
  A NIF interface to the C/C++ Cuckoo Cycle implementation of
  John Tromp:  https://github.com/tromp/cuckoo
  White paper: https://github.com/tromp/cuckoo/blob/master/doc/cuckoo.pdf?raw=true
  """

  @nonce_range 1000000000000000000000000
  @on_load { :init, 0 }

  def init do
    path = Application.get_env(:aecore, :env)[:test_nif_path]
    :ok = :erlang.load_nif(path, 0)
  end


  def generate(data, difficulty, retries) do
    nonce = pick_nonce()
    generate(data, nonce, difficulty, 7, 5, retries)
  end

  @doc """
  %% Proof of Work generation, multiple attempts
  """

  def generate(data, nonce, difficulty, trims, threads, retries) do
    hash = :base64.encode_to_string(Aecore.Utils.Sha256.hash(data))
    generate_hashed(hash, nonce, difficulty, trims, threads, retries)
  end


  @doc """
  Proof of Work verification (with difficulty check)
  """

  def verify(data, nonce, soln, difficulty) do
    hash = :base64.encode_to_string(Aecore.Utils.Sha256.hash(data))
    case test_target(soln, difficulty) do
      true ->
        verify(hash, nonce, soln)
      false ->
        false
    end
  end

  @doc """
  Adjust difficulty so that generation of new blocks proceeds at the expected pac
  """
  def recalculate_difficulty(difficulty, expected, actual) do
    diffint = Aecore.Sha256.scientific_to_integer(difficulty)
    Aecore.Sha256.integer_to_scientific(max(1, div((diffint*expected), actual)))
  end

  ###=============================================================================
  ### Internal functions
  ###=============================================================================

  @doc """
  Proof of Work generation: use the hash provided and try consecutive nonces
  """
  defp generate_hashed(_,_, _,_,_, 0) do
    {:error, :generation_count_exhausted}
  end
  defp generate_hashed(hash, nonce, target, trims, threads, retries) when retries > 0 do
    nonce32 = :erlang.band(nonce,2147483647)
    case generate_single(hash, nonce32, trims, threads) do
      {:error, :no_solutions} ->
        generate_hashed(hash, nonce + 1, target, trims, threads, retries - 1)
      {:ok, soln} = result ->
        case test_target(soln, target) do
          true ->
            {:ok, {nonce, soln}}
          false ->
            new_nonce =
              case nonce do
                2147483647 -> 0
                _          -> nonce + 1
              end
            generate_hashed(hash, new_nonce, target, trims, threads, retries - 1)
        end
      any ->
        IO.inspect any
    end
  end

  @doc """
  Proof of Work generation, a single attempt
  """
  def generate_single(header, nonce, trims, theards) do
    :nif_library_not_loaded
  end

  @doc """
  Proof of Work verification (without difficulty check)
  """
  def verify(_Hash, _Nonce, _Soln) do
    :nif_library_not_loaded
  end

  @doc """
  Fetch the size of solution elements
  """
  @spec get_node_size() :: integer()
  defp get_node_size() do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @doc """
  White paper, section 9: rather than adjusting the nodes/edges ratio, a
  hash-based difficulty is suggested: the sha256 hash of the cycle nonces
  is restricted to be under the difficulty value (0 < difficulty < 2^256)
  """
  defp test_target(soln, target) do
    nodesize = get_node_size()
    bin  = solution_to_binary(:lists.sort(soln), nodesize * 8, <<>>)
    hash = Aecore.Utils.Sha256.hash(bin)
    Aecore.Utils.Sha256.binary_to_scientific(hash) < target
  end

  @doc """
  Convert solution (a list of 42 numbers) to a binary
  """
  defp solution_to_binary([], _Bits, acc) do
    acc
  end
  defp solution_to_binary([h | t], bits, acc) do
    solution_to_binary(t, bits, acc <> <<h::size(bits) >>)
  end

  @spec pick_nonce() :: integer()
  defp pick_nonce() do
	:rand.uniform(:erlang.band(@nonce_range, 2147483647))
  end

end
