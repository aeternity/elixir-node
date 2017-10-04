defmodule Aecore.Pow.Hashcash do
  @moduledoc """
  Hashcash proof of work
  """

  @doc """
  Verify a nonce, returns :true | :false
  """
  @spec verify(map(),  integer()) :: boolean()
  def verify(%Aecore.Structures.Header{}=block_header, diff) do
    {answer, target} = do_generate(block_header, diff)
    verify(answer, target)
  end

  def verify(answer, target) do
    String.starts_with?(answer, target)
  end

  @doc """
  Find a nonce
  """
  @spec generate(map(), integer()) ::
  {:ok, %Aecore.Structures.Header{} } | {:error, term()}
  def generate(%Aecore.Structures.Header{nonce: nonce}=block_header, diff) do
    {answer, target} = do_generate(block_header, diff)
    case verify(answer, target) do
      true  -> {:ok, block_header}
      false -> generate(%{block_header |
                         nonce: nonce + 1}, diff)
    end
  end

  ## takes an integer and returns
  ## concatenated zeros depending
  ## on that integer
  defp get_target(diff) do
    to_string(
      for zeros <- 1..diff, do: "0")
  end

  defp do_generate(block_header, diff) do
    target = get_target(diff)
    data   = :erlang.term_to_binary(block_header)
    hash   = :crypto.hash(:sha256, data)
    answer = Base.encode16(hash)
    {answer, target}
  end

end
