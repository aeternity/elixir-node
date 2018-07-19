defmodule Aecore.Chain.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Chain.Header
  alias Aeutil.Bits
  alias Aecore.Keys.Wallet

  @txs_hash_size 32
  @header_hash_size 32
  @root_hash_size 32
  @pow_size 168
  @pubkey_size 33

  @type t :: %Header{
          height: non_neg_integer(),
          prev_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          target: non_neg_integer(),
          nonce: non_neg_integer(),
          time: non_neg_integer(),
          miner: Wallet.pubkey(),
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
          Wallet.pubkey(),
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

  def base58c_encode(bin) do
    Bits.encode58c("bh", bin)
  end

  def base58c_decode(<<"bh$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  @spec encode_to_binary(t()) :: binary()
  def encode_to_binary(%Header{} = header) do
    <<
      header.version::64,
      header.height::64,
      header.prev_hash::binary-size(@header_hash_size),
      header.txs_hash::binary-size(@txs_hash_size),
      header.root_hash::binary-size(@root_hash_size),
      header.target::64,
      pow_to_binary(header.pow_evidence)::binary-size(@pow_size),
      header.nonce::64,
      header.time::64,
      # pubkey should be adjusted to 32 bytes.
      header.miner::binary-size(@pubkey_size)
    >>
  end

  def header_to_binary(_) do
    {:error, "#{__MODULE__}: Illegal header structure serialization"}
  end

  @spec binary_to_header(binary()) :: {:ok, Header.t()} | {:error, String.t()}
  def binary_to_header(<<
        version::64,
        height::64,
        prev_hash::binary-size(@header_hash_size),
        txs_hash::binary-size(@txs_hash_size),
        root_hash::binary-size(@root_hash_size),
        target::64,
        pow_evidence_bin::binary-size(@pow_size),
        nonce::64,
        # pubkey should be adjusted to 32 bytes.
        time::64,
        miner::binary-size(@pubkey_size)
      >>) do
    with {:ok, pow_evidence} <- binary_to_pow(pow_evidence_bin) do
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
    else
      {:error, _} = error -> error
    end
  end

  def binary_to_header(_) do
    {:error, "#{__MODULE__}: binary_to_header: Invalid header binary serialization"}
  end

  @spec pow_to_binary(list()) :: binary() | list()
  def pow_to_binary(pow) do
    if is_list(pow) and Enum.count(pow) == 42 do
      list_of_pows =
        for evidence <- pow, into: <<>> do
          <<evidence::32>>
        end

      serialize_pow(list_of_pows, <<>>)
    else
      bits_size = 8 * @pow_size
      <<0::size(bits_size)>>
    end
  end

  @spec binary_to_pow(binary()) :: {:ok, list()} | {:error, atom()}
  def binary_to_pow(<<pow_bin_list::@pow_size>>) do
    deserialize_pow(pow_bin_list, [])
  end

  def binary_to_pow(_) do
    {:error, "#{__MODULE__} : Illegal PoW serialization"}
  end

  @spec serialize_pow(binary(), binary()) :: binary()
  defp serialize_pow(pow, acc) when pow != <<>> do
    <<elem::binary-size(4), rest::binary>> = pow
    serialize_pow(rest, acc <> elem)
  end

  defp serialize_pow(<<>>, acc) do
    acc
  end

  defp deserialize_pow(<<pow::32, rest::binary>>, acc) do
    deserialize_pow(rest, List.insert_at(acc, -1, pow))
  end

  defp deserialize_pow(<<>>, acc) do
    if Enum.count(Enum.filter(acc, fn x -> is_integer(x) and x >= 0 end)) == 42 do
      {:ok, acc}
    else
      {:error, "#{__MODULE__} : Illegal PoW serialization"}
    end
  end
end
