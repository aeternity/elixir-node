defmodule Aecore.Pow.Cuckoo do
  @moduledoc """
  A library providing Cuckoo Cycle PoW generation and verification.
  A NIF interface to the C/C++ Cuckoo Cycle implementation of
  John Tromp:  https://github.com/tromp/cuckoo
  White paper: https://github.com/tromp/cuckoo/blob/master/doc/cuckoo.pdf?raw=true

  Source file used for building this:
    - https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_pow_cuckoo.erl
    - https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_pow.erl
  """
  require Logger

  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Header
  alias Aecore.Pow.Hashcash

  @trims 7
  @threads 5
  @mersenne_prime 2_147_483_647

  @on_load {:init, 0}

  def init do
    path = Application.get_env(:aecore, :pow)[:nif_path]
    :ok  = :erlang.load_nif(path, 0)
  end

  @doc """
  Proof of Work verification (with difficulty check)
  """
  @spec verify(map) :: boolean()
  def verify(%Header{nonce: nonce,
                     difficulty_target: difficulty,
                     pow_evidence: soln} = header) do
    hash = hash_header(%{header | pow_evidence: nil})
    case test_target(soln, difficulty) do
      true  -> verify(hash, nonce, soln)
      false -> false
    end
  end


  @doc """
  Find a nonce, by calling nif.Returns {:ok, %Header{}}
  """
  @spec generate(map) :: {:ok, map}
  def generate(%{} = header) do
    generate_process(header, hash_header(header))
  end

  def generate_process(header, hash) do
    case generate_single(hash, header.nonce, @trims, @threads) do
      {:error, :no_solutions} ->
        generate(%{header | nonce: next_nonce(header.nonce)})
      {:ok, soln} ->
        test_target(%{header | pow_evidence: soln})
    end
  end

  ###=============================================================================
  ### Internal functions
  ###=============================================================================

  ## Proof of Work generation, a single attempt.
  ## We are making call to a nif and the return is
  ## {:ok, solution :: list} | {:error, :no_solutions}
  ## When your NIF is loaded, it will override this function.
  defp generate_single(_header, _nonce, _trims, _theards) do
    :nif_library_not_loaded
  end

  defp test_target(%{pow_evidence: soln, difficulty_target: target} = header) do
    case test_target(soln, target) do
      true  ->
        {:ok, header}
      false ->
        generate(%{header |
                   nonce: next_nonce(header.nonce),
                   pow_evidence: nil})
    end
  end

  ## White paper, section 9: rather than adjusting the nodes/edges ratio, a
  ## hash-based difficulty is suggested: the sha256 hash of the cycle nonces
  ## is restricted to be under the difficulty value (0 < difficulty < 2^256)
  @spec test_target(soln :: list, target :: integer) :: true | false
  defp test_target(soln, target) do
    nodesize = get_node_size()
    bin = solution_to_binary(:lists.sort(soln), nodesize * 8, <<>>)
    Hashcash.generate(:cuckoo, bin, target)
  end

  @spec hash_header(header :: map) :: list
  defp hash_header(header) do
    :base64.encode_to_string(BlockValidation.block_header_hash(header))
  end

  ## Proof of Work verification (without difficulty check)
  ## We are making call to a nif and the return is boolean()
  ## When your NIF is loaded, it will override this function.
  defp verify(_hash, _nonce, _soln) do
    :nif_library_not_loaded
  end

  ## Fetch the size of solution elements
  ## If nif is not loaded - stops the
  ## execution of the calling process with the reason.
  ## When your NIF is loaded, it will override this function.
  @spec get_node_size() :: integer
  defp get_node_size() do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  ## Convert solution (a list of 42 numbers) to a binary
  defp solution_to_binary([], _Bits, acc) do
    acc
  end
  defp solution_to_binary([h | t], bits, acc) do
    solution_to_binary(t, bits, acc <> <<h::size(bits) >>)
  end

  defp next_nonce(@mersenne_prime), do: 0
  defp next_nonce(nonce), do:  nonce + 1

end
