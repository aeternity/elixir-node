defmodule Aecore.Pow.Hashcash do
  @moduledoc """
  Hashcash proof of work
  """

  alias Aeutil.Scientific
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Header

  use Bitwise

  @doc """
  Verify a nonce, returns :true | :false
  """
  @spec verify(map()) :: boolean()
  def verify(%Aecore.Structures.Header{} = block_header) do
    block_header_hash = BlockValidation.block_header_hash(block_header)
    verify(block_header_hash, block_header.target)
  end

  @spec verify(binary(), non_neg_integer()) :: boolean()
  def verify(block_header_hash, difficulty) do
    {exp, significand} = Scientific.break_scientific(difficulty)
    length = byte_size(block_header_hash)
    zeros = 8 * max(0, length - exp)

    cond do
      exp >= 0 and exp < 3 ->
        Scientific.compare_bin_to_significand(
          block_header_hash,
          bsr(significand, 8 * (3 - exp)),
          zeros,
          8 * exp
        )

      exp > length and exp < length + 3 ->
        skip = 8 * (exp - length)
        compare = 24 - skip

        case bsr(significand, compare) do
          0 ->
            Scientific.compare_bin_to_significand(
              block_header_hash,
              bsl(significand, skip),
              0,
              24
            )

          _ ->
            :error
        end

      exp >= 0 ->
        Scientific.compare_bin_to_significand(block_header_hash, significand, zeros, 24)

      exp < 0 ->
        bits = 8 * length
        block_header_hash == <<0::size(bits)>>

      true ->
        :error
    end
  end

  @doc """
  Find a nonce
  """
  @spec generate(Header.t(), non_neg_integer()) :: {:ok, Header.t()} | {:error, term()}
  def generate(%Header{nonce: nonce} = block_header, start_nonce) do
    block_header_hash = BlockValidation.block_header_hash(block_header)

    case verify(block_header_hash, block_header.target) do
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
end
