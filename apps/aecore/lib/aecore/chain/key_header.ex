defmodule Aecore.Chain.KeyHeader do
  @moduledoc """
  Module defining the KeyHeader structure
  """
  alias Aecore.Chain.KeyHeader
  alias Aecore.Keys
  alias Aeutil.Hash

  @tag 1
  @tag_size 1
  @unused_flag 0
  @unused_flags_size 31

  @version_size 32
  @height_size 64
  @header_hash_size 32
  @root_hash_size 32
  @target_size 32
  @pow_size 168
  @nonce_size 64
  @time_size 64
  @pubkey_size 32
  @pow_element_size 4
  @pow_element_size_bits @pow_element_size * 8
  @pow_length 42

  @type t :: %KeyHeader{
          height: non_neg_integer(),
          prev_hash: binary(),
          prev_key_hash: binary(),
          root_hash: binary(),
          target: non_neg_integer(),
          nonce: non_neg_integer(),
          time: non_neg_integer(),
          miner: Keys.pubkey(),
          version: non_neg_integer(),
          pow_evidence: list(non_neg_integer()),
          beneficiary: Keys.pubkey()
        }

  defstruct [
    :height,
    :prev_hash,
    :prev_key_hash,
    :root_hash,
    :target,
    :nonce,
    :time,
    :miner,
    :version,
    :pow_evidence,
    :beneficiary
  ]

  use ExConstructor

  @spec hash(KeyHeader.t()) :: binary()
  def hash(%KeyHeader{} = header) do
    header
    |> encode_to_binary()
    |> Hash.hash()
  end

  @spec encode_to_binary(KeyHeader.t()) :: binary()
  def encode_to_binary(%KeyHeader{
        height: height,
        prev_hash: prev_hash,
        prev_key_hash: prev_key_hash,
        root_hash: root_hash,
        target: target,
        nonce: nonce,
        time: time,
        miner: miner,
        version: version,
        pow_evidence: pow_evidence,
        beneficiary: beneficiary
      }) do
    flags = flags()
    unused_flags_size_bytes = trunc((@tag_size + @unused_flags_size) / 8)

    <<
      version::@version_size,
      flags::binary-size(unused_flags_size_bytes),
      height::@height_size,
      prev_hash::binary-size(@header_hash_size),
      prev_key_hash::binary-size(@header_hash_size),
      root_hash::binary-size(@root_hash_size),
      miner::binary-size(@pubkey_size),
      beneficiary::binary-size(@pubkey_size),
      target::@target_size,
      pow_to_binary(pow_evidence)::binary-size(@pow_size),
      nonce::@nonce_size,
      time::@time_size
    >>
  end

  @spec decode_from_binary(binary()) :: {:ok, KeyHeader.t()} | {:error, String.t()}
  def decode_from_binary(<<
        version::@version_size,
        @tag::@tag_size,
        @unused_flag::@unused_flags_size,
        height::@height_size,
        prev_hash::binary-size(@header_hash_size),
        prev_key_hash::binary-size(@header_hash_size),
        root_hash::binary-size(@root_hash_size),
        miner::binary-size(@pubkey_size),
        beneficiary::binary-size(@pubkey_size),
        target::@target_size,
        pow_evidence_bin::binary-size(@pow_size),
        nonce::@nonce_size,
        time::@time_size
      >>) do
    case binary_to_pow(pow_evidence_bin) do
      {:ok, pow_evidence} ->
        {:ok,
         %KeyHeader{
           height: height,
           prev_hash: prev_hash,
           prev_key_hash: prev_key_hash,
           root_hash: root_hash,
           target: target,
           nonce: nonce,
           time: time,
           miner: miner,
           version: version,
           pow_evidence: pow_evidence,
           beneficiary: beneficiary
         }}

      {:error, _} = error ->
        error
    end
  end

  defp pow_to_binary(pow) do
    if is_list(pow) and Enum.count(pow) == @pow_length do
      list_of_pows =
        for evidence <- pow, into: <<>> do
          <<evidence::@pow_element_size_bits>>
        end

      serialize_pow(list_of_pows, <<>>)
    else
      bits_size = 8 * @pow_size
      <<0::size(bits_size)>>
    end
  end

  defp binary_to_pow(<<pow_bin_list::binary-size(@pow_size)>>) do
    deserialize_pow(pow_bin_list, [])
  end

  defp binary_to_pow(_) do
    {:error, "#{__MODULE__} : Illegal PoW serialization"}
  end

  defp serialize_pow(<<elem::binary-size(@pow_element_size), rest::binary>>, acc) do
    serialize_pow(rest, acc <> elem)
  end

  defp serialize_pow(<<>>, acc) do
    acc
  end

  defp deserialize_pow(<<pow::@pow_element_size_bits, rest::binary>>, acc) do
    deserialize_pow(rest, List.insert_at(acc, -1, pow))
  end

  defp deserialize_pow(<<>>, acc) do
    if Enum.count(Enum.filter(acc, fn x -> is_integer(x) and x >= 0 end)) == @pow_length do
      {:ok, acc}
    else
      {:error, "#{__MODULE__} : Illegal PoW serialization"}
    end
  end

  defp flags do
    <<@tag::@tag_size, @unused_flag::@unused_flags_size>>
  end
end
