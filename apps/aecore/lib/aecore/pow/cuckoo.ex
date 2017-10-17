defmodule Aecore.Pow.Cuckoo do
  @moduledoc """
  A library providing Cuckoo Cycle PoW generation and verification.
  A NIF interface to the C/C++ Cuckoo Cycle implementation of
  John Tromp:  https://github.com/tromp/cuckoo
  White paper: https://github.com/tromp/cuckoo/blob/master/doc/cuckoo.pdf?raw=true
  """
  require Logger

  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Pow.Hashcash

  @nonce_range 1000000000000000000000000
  @trims 7
  @threads 5
  @mersenne_prime 2147483647

  @on_load { :init, 0 }

  def init do
    path = Application.get_env(:aecore, :pow)[:nif_path]
    :ok  = :erlang.load_nif(path, 0)
  end

  @doc """
  Proof of Work verification (with difficulty check)
  """
  def verify(%{nonce: nonce,
               difficulty_target: difficulty,
               pow_evidence: soln}=header) do
    hash = hash_header(%{header | pow_evidence: nil})
    case test_target(soln, difficulty) do
      true  -> verify(hash, nonce, soln)
      false -> false
    end
  end

  def generate(header) do
    header  = %{header | nonce: pick_nonce()}
    hash    = hash_header(header)
    generate_process(header, hash)
  end

  def generate_process(header, hash) do
    case generate_single(hash, header.nonce, @trims, @threads) do
      {:error, :no_solutions} ->
        header = %{header | nonce: next_nonce(header.nonce)}
        hash   = hash_header(header)
        generate_process(header, hash)
      {:ok, soln} ->
            test_target(%{header | pow_evidence: soln})
    end
  end

  ###=============================================================================
  ### Internal functions
  ###=============================================================================

  ##Proof of Work generation, a single attempt.External call to the nif
  defp generate_single(header, nonce, trims, theards) do
    :nif_library_not_loaded
  end

  defp test_target(%{pow_evidence: soln, difficulty_target: target}=header) do
    case test_target(soln, target) do
      true  ->
        {:ok, header}
      false ->
        header = %{header | nonce: next_nonce(header.nonce)}
        hash   = hash_header(header)
        generate_process(header, hash)
    end
  end

  defp hash_header(header) do
    :base64.encode_to_string(BlockValidation.block_header_hash(header))
  end


  ##Proof of Work verification (without difficulty check)
  defp verify(_Hash, _Nonce, _Soln) do
    :nif_library_not_loaded
  end

  ##Fetch the size of solution elements
  @spec get_node_size() :: integer()
  defp get_node_size() do
    :erlang.nif_error(:nif_library_not_loaded)
  end


  ##White paper, section 9: rather than adjusting the nodes/edges ratio, a
  ##hash-based difficulty is suggested: the sha256 hash of the cycle nonces
  ##is restricted to be under the difficulty value (0 < difficulty < 2^256)
  defp test_target(soln, target) do
    nodesize = get_node_size()
    bin  = solution_to_binary(:lists.sort(soln), nodesize * 8, <<>>)
    Hashcash.generate(:cuckoo, bin, target)
  end


  ##Convert solution (a list of 42 numbers) to a binary
  defp solution_to_binary([], _Bits, acc) do
    acc
  end
  defp solution_to_binary([h | t], bits, acc) do
    solution_to_binary(t, bits, acc <> <<h::size(bits) >>)
  end

  @spec pick_nonce() :: integer()
  def pick_nonce() do
    :rand.uniform(:erlang.band(@nonce_range, @mersenne_prime))
  end

  defp next_nonce(214748364) do
    0
  end
  defp next_nonce(nonce) do
    :erlang.band(nonce + 1, @mersenne_prime)
  end

end
