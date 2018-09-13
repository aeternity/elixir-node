defmodule Aecore.Chain.Header do
  @moduledoc """
  Module defining the structure of the block header
  """

  alias Aecore.Chain.Header
  alias Aeutil.{Hash, Bits}
  alias Aecore.Keys
  alias Aeutil.Bits

  @header_version_size 64
  @header_height_size 64
  @txs_hash_size 32
  @header_hash_size 32
  @root_hash_size 32
  @header_target_size 64
  @pow_size 168
  @header_nonce_size 64
  @header_time_size 64
  @pubkey_size 32
  @pow_element_size 4
  @pow_element_size_bits @pow_element_size * 8
  @pow_length 42

  @typedoc "Structure of the Header Transaction type"
  @type t :: %Header{
          height: non_neg_integer(),
          prev_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          target: non_neg_integer(),
          nonce: non_neg_integer(),
          time: non_neg_integer(),
          miner: Keys.pubkey(),
          version: non_neg_integer()
        }

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :root_hash,
    :target,
    :nonce,
    :time,
    :miner,
    :version,
    :pow_evidence
  ]

  use ExConstructor

  @spec create(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Keys.pubkey(),
          non_neg_integer()
        ) :: Header.t()
  def create(height, prev_hash, txs_hash, root_hash, target, nonce, time, miner, version) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      target: target,
      nonce: nonce,
      time: time,
      miner: miner,
      version: version
    }
  end

  @spec hash(Header.t()) :: binary()
  def hash(%Header{} = header) do
    header
    |> encode_to_binary()
    |> Hash.hash()
  end

  @spec base58c_encode(binary()) :: String.t()
  def base58c_encode(bin) do
    Bits.encode58c("bh", bin)
  end

  @spec base58c_decode(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode(<<"bh$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  @spec encode_to_binary(Header.t()) :: binary()
  def encode_to_binary(%Header{
        version: version,
        height: height,
        prev_hash: prev_hash,
        txs_hash: txs_hash,
        root_hash: root_hash,
        target: target,
        pow_evidence: pow_evidence,
        nonce: nonce,
        time: time,
        miner: miner
      }) do
    <<
      version::@header_version_size,
      height::@header_height_size,
      prev_hash::binary-size(@header_hash_size),
      txs_hash::binary-size(@txs_hash_size),
      root_hash::binary-size(@root_hash_size),
      target::@header_target_size,
      pow_to_binary(pow_evidence)::binary-size(@pow_size),
      nonce::@header_nonce_size,
      time::@header_time_size,
      miner::binary-size(@pubkey_size)
    >>
  end

  def encode_to_binary(_) do
    {:error, "#{__MODULE__}: Illegal header structure serialization"}
  end

  @spec decode_from_binary(binary()) :: {:ok, Header.t()} | {:error, String.t()}
  def decode_from_binary(<<
        version::@header_version_size,
        height::@header_height_size,
        prev_hash::binary-size(@header_hash_size),
        txs_hash::binary-size(@txs_hash_size),
        root_hash::binary-size(@root_hash_size),
        target::@header_target_size,
        pow_evidence_bin::binary-size(@pow_size),
        nonce::@header_nonce_size,
        time::@header_time_size,
        miner::binary-size(@pubkey_size)
      >>) do
    case binary_to_pow(pow_evidence_bin) do
      {:ok, pow_evidence} ->
        {:ok,
         %Header{
           height: height,
           nonce: nonce,
           pow_evidence: pow_evidence,
           prev_hash: prev_hash,
           root_hash: root_hash,
           target: target,
           time: time,
           txs_hash: txs_hash,
           version: version,
           miner: miner
         }}

      {:error, _} = error ->
        error
    end
  end

  def decode_from_binary(_) do
    {:error, "#{__MODULE__}: binary_to_header: Invalid header binary serialization"}
  end

  @spec pow_to_binary(list()) :: binary() | list()
  def pow_to_binary(pow) do
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

  @spec binary_to_pow(binary()) :: {:ok, list()} | {:error, atom()} | {:error, String.t()}
  def binary_to_pow(<<pow_bin_list::binary-size(@pow_size)>>) do
    deserialize_pow(pow_bin_list, [])
  end

  def binary_to_pow(_) do
    {:error, "#{__MODULE__} : Illegal PoW serialization"}
  end

  @spec serialize_pow(binary(), binary()) :: binary()
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
end
