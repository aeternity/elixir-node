defmodule Aeutil.Bits do
  @moduledoc """
  Taken from http://minhajuddin.com/2016/11/01/how-to-extract-bits-from-a-binary-in-elixir/
  License: CC BY-SA 3.0
  """

  @spec encode58c(binary(), binary()) :: binary()
  def encode58c(prefix, payload) when is_binary(payload) do
    prefix <> "$" <> encode58(payload)
  end

  defp encode58(payload) do
    checksum = generate_checksum(payload)

    payload
    |> Kernel.<>(checksum)
    |> :base58.binary_to_base58()
    |> to_string()
  end

  defp generate_checksum(payload) do
    <<checksum::binary-size(4), _::binary>> =
      :crypto.hash(:sha256, :crypto.hash(:sha256, payload))

    checksum
  end

  def decode58(payload) do
    decoded_payload =
      payload
      |> String.to_charlist()
      |> :base58.base58_to_binary()

    bsize = byte_size(decoded_payload) - 4
    <<data::binary-size(bsize), _checksum::binary-size(4)>> = decoded_payload
    data
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
