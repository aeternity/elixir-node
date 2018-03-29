defmodule Aecore.Pow.Hashcash do
  alias Aeutil.Scientific
  use Bitwise
  @moduledoc """
  Hashcash proof of work
  """

  @doc """
  Verify a nonce, returns :true | :false
  """

  alias Aeutil.Bits
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Header

  @spec verify(map()) :: boolean()
  def verify(%Aecore.Structures.Header{} = block_header) do
    block_header_hash = BlockValidation.block_header_hash(block_header)
    verify(block_header_hash, block_header.difficulty_target)
  end

  @spec verify(binary(), integer()) :: boolean()
  def verify(block_header_hash, difficulty) do
    {exp, significand} = Scientific.break_scientific(difficulty)
    length = byte_size(block_header_hash)
    zeros = 8*max(0, length - exp)
    case exp do
      _exp when _exp >= 0 and _exp < 3 ->
        Scientific.compare_bin_to_significand(
          block_header_hash,
          bsr(significand, 8*(3 - exp)),
          zeros,
          8*exp)

      _ when exp > length and exp < length + 3 ->
        skip = 8*(exp - length)
        compare = 24 - skip

        case bsr(significand, compare) do
          0 ->
            Scientific.compare_bin_to_significand(
              block_header_hash,
              bsl(significand, skip),
              0,
              24)
          _ ->
            :error
        end

      _exp when _exp >= 0 ->
        Scientific.compare_bin_to_significand(block_header_hash,
          significand,
          zeros,
          24)

      _exp when _exp <0 ->
        bits = 8*length
        block_header_hash == <<0 :: size(bits)>>
    end
  end

  @doc """
  Find a nonce
  """
  @spec generate(Header.t(), integer()) :: {:ok, Header.t()} | {:error, term()}
  def generate(%Header{nonce: nonce} = block_header, start_nonce) do
    block_header_hash = BlockValidation.block_header_hash(block_header)

    case verify(block_header_hash, block_header.difficulty_target) do
      true ->
        {:ok, block_header}

      false ->
        if nonce <= start_nonce do
          generate(%{block_header | nonce: nonce + 1}, start_nonce)
        else
          {:error, "no solution found"}
        end
    end
  end

  # TODO: this should be renamed or removed
  @spec generate(:cuckoo, binary(), integer()) :: boolean()
  def generate(:cuckoo, data, target) do
    verify(data, target)
  end
end
