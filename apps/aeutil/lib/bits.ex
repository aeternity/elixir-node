defmodule Aeutil.Bits do
  @moduledoc """
  Taken from http://minhajuddin.com/2016/11/01/how-to-extract-bits-from-a-binary-in-elixir/
  License: CC BY-SA 3.0
  """

  def bech32_encode(prefix, bin) do
    SegwitAddr.encode(prefix, 0, :binary.bin_to_list(bin))
  end

  def bech32_decode(bech32) do
    case SegwitAddr.decode(bech32) do
      {:ok, {_, _, bin_list}} -> :binary.list_to_bin(bin_list)
      {:error, _} = error -> error
    end
  end

  # this is the public api which allows you to pass any binary representation
  def extract(str) when is_binary(str) do
    extract(str, [])
  end

  # this function does the heavy lifting by matching the input binary to
  # a single bit and sends the rest of the bits recursively back to itself
  defp extract(<<b::size(1), bits::bitstring>>, acc) when is_bitstring(bits) do
    extract(bits, [b | acc])
  end

  # this is the terminal condition when we don't have anything more to extract
  defp extract(<<>>, acc), do: acc |> Enum.reverse()
end
