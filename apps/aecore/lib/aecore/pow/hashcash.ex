defmodule Aecore.Pow.Hashcash do
  @moduledoc """
  Hashcash proof of work
  """

  @doc """
  Verify a nonce, returns :true | :false
  """
  @spec verify(map()) :: boolean()
  def verify(%Aecore.Structures.Header{}=block_header) do
    block_header_hash   = generate_hash(block_header)
    verify(block_header_hash, block_header.difficulty_target)
  end

  @spec verify(string()::integer()) :: boolean()
  def verify(block_header_hash, difficulty) do
    String.starts_with?(block_header_hash, get_target_zeros(difficulty))
  end

  @doc """
  Find a nonce
  """
  @spec generate(map()) ::
  {:ok, %Aecore.Structures.Header{} } | {:error, term()}
  def generate(%Aecore.Structures.Header{nonce: nonce}=block_header) do
    block_header_hash = generate_hash(block_header)
    case verify(block_header_hash, block_header.difficulty_target) do
      true  -> {:ok, block_header}
      false -> generate(%{block_header |
                         nonce: nonce + 1})
    end
  end

  ## takes an integer and returns
  ## concatenated zeros depending
  ## on that integer
  defp get_target_zeros(difficulty) do
    to_string(for zeros <- 1..difficulty, do: "0")
  end

  defp generate_hash(block_header) do
    data   = :erlang.term_to_binary(block_header)
    hash   = :crypto.hash(:sha256, data)
    block_header_hash = Base.encode16(hash)
  end

end
