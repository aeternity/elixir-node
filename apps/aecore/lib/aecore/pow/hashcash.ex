defmodule Aecore.Pow.Hashcash do
  @moduledoc """
  Hashcash proof of work
  """

  alias Aeutil.Bits
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Header

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
    block_header_hash
    |> Bits.extract()
    |> Enum.take_while(fn bit -> bit == 0 end)
    |> Enum.count() >= difficulty
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
