# Taken from http://minhajuddin.com/2016/11/01/how-to-extract-bits-from-a-binary-in-elixir/
# License: CC BY-SA 3.0
defmodule Aeutil.Bits do
  @prefix_list ["ak$", "bh$", "bs$", "tx$", "bx$", "ok$", "cs$", "tr$"]

  def encode58c(prefix, payload) when is_binary(payload) do
    case prefix do
      :account_pubkey ->
        "ak" <> "$" <> encode58(payload)

      :block_hash ->
        "bh" <> "$" <> encode58(payload)

      :block_state_hash ->
        "bs" <> "$" <> encode58(payload)

      :transaction ->
        "tx" <> "$" <> encode58(payload)

      :block_tx_hash ->
        "bx" <> "$" <> encode58(payload)

      :oracle_pubkey ->
        "ok" <> "$" <> encode58(payload)

      :chain_state ->
        "cs" <> "$" <> encode58(payload)

      :root_hash ->
        "tr" <> "$" <> encode58(payload)
    end
  end

  def decode58c(payload) when is_binary(payload) do
    {data_prefix, bin} = String.split_at(payload, 3)

    if Enum.member?(@prefix_list, data_prefix) do
      {data_prefix, Kernel.to_string(decode58(bin))}
    else
      {:error, "Invalid prefix"}
    end
  end

  def check_string(payload) do
    <<payload::binary-size(4), _::binary>> = :crypto.hash(:sha256, :crypto.hash(:sha256, payload))
    payload
  end

  # this is the public api which allows you to pass any binary representation
  def extract(str) when is_binary(str) do
    extract(str, [])
  end

  defp encode58(payload) do
    checksum = check_string(payload)
    Kernel.to_string(:base58.binary_to_base58(payload <> checksum))
  end

  defp decode58(payload) do
    decoded_p = :base58.base58_to_binary(String.to_charlist(payload))
    bsize = Kernel.byte_size(decoded_p) - 4
    <<data::binary-size(bsize), _checksum::binary-size(4)>> = decoded_p
    _checksum = check_string(data)
    data
  end

  # this function does the heavy lifting by matching the input binary to
  # a single bit and sends the rest of the bits recursively back to itself
  defp extract(<<b::size(1), bits::bitstring>>, acc) when is_bitstring(bits) do
    extract(bits, [b | acc])
  end

  # this is the terminal condition when we don't have anything more to extract
  defp extract(<<>>, acc), do: acc |> Enum.reverse()
end
