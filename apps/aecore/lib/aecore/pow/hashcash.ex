defmodule Aecore.Pow.Hashcash do
  @moduledoc """
  Hashcash proof of work
  """

  @nonce_range 1000000000000000000000000

  @doc """
  Verify a nonce
  """
  def verify(challenge, nonce, diff) when is_binary(challenge) do
    target = get_target(diff)
    data   = <<challenge :: binary, nonce :: 256>>
    hash   = :crypto.hash(:sha256, data)
    answer = Base.encode16(hash)
    verify(answer, target)
  end
  def verify(challenge, nonce, diff) do
    verify(:erlang.term_to_binary(challenge), nonce, diff)
  end

  defp verify(answer, target) do
    String.starts_with?(answer, target)
  end

  @doc """
  Find a nonce
  """
  @spec generate(binary() | term(), integer()) ::
  {:ok, nonce :: integer()} | {:error, term()}
  def generate(challenge, diff) when is_binary(challenge) do
    nonce  = generate_nonce()
    target = get_target(diff)
    generate(challenge, target, nonce)
  end
  def generate(challenge, diff) do
    generate(:erlang.term_to_binary(challenge), diff)
  end

  defp generate(challenge, target, nonce) do
    data   = <<challenge :: binary, nonce :: 256>>
    hash   = :crypto.hash(:sha256, data)
    answer = Base.encode16(hash)
    case verify(answer, target) do
      true  -> {:ok, nonce}
      false -> generate(challenge, target, nonce + 1)
    end
  end

  defp generate_nonce() do
    :rand.uniform(@nonce_range)
  end

  defp get_target(diff) do
    to_string(
      for z <- 1..diff, do: "0")
  end

end
