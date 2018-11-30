defmodule Aecore.Chain.MicroHeader do
  @moduledoc """
  Module defining the MicroHeader structure
  """
  alias Aecore.Chain.MicroHeader

  @tag 0
  @tag_size 1
  @unused_flag 0
  @unused_flags_size 31

  @version_size 32
  @height_size 64
  @header_hash_size 32
  @root_hash_size 32
  @txs_hash_size 32
  @time_size 64
  @signature_size 64
  @version 1
  # @pof_flag_size 8
  # @header_min_bytes 216
  # @pof_hash_size 32
  @flags_byte_size trunc((@tag_size + @unused_flags_size) / 8)

  @type t :: %MicroHeader{
          height: non_neg_integer(),
          pof_hash: binary(),
          prev_hash: binary(),
          prev_key_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          time: non_neg_integer(),
          version: non_neg_integer(),
          signature: binary()
        }

  defstruct [
    :height,
    :pof_hash,
    :prev_hash,
    :prev_key_hash,
    :txs_hash,
    :root_hash,
    :time,
    :version,
    :signature
  ]

  @spec encode_to_binary(MicroHeader.t()) :: binary()
  def encode_to_binary(%MicroHeader{
        height: height,
        # pof_hash: pof_hash,
        prev_hash: prev_hash,
        prev_key_hash: prev_key_hash,
        txs_hash: txs_hash,
        root_hash: root_hash,
        time: time,
        version: version,
        signature: signature
      }) do
    flags = flags()
    flags_byte_size = trunc((@tag_size + @unused_flags_size) / 8)

    <<
      version::@version_size,
      flags::binary-size(flags_byte_size),
      height::@height_size,
      prev_hash::binary-size(@header_hash_size),
      prev_key_hash::binary-size(@header_hash_size),
      root_hash::binary-size(@root_hash_size),
      txs_hash::binary-size(@txs_hash_size),
      time::@time_size,
      signature::binary-size(@signature_size)
    >>
  end

  @spec flags() :: binary()
  def flags do
    <<@tag::@tag_size, @unused_flag::@unused_flags_size>>
  end

  @spec decode_from_binary(binary()) :: {:error, String.t()} | {:ok, MicroHeader.t()}
  def decode_from_binary(
        # pof_flag::@pof_flag_size,
        <<@version::@version_size, @tag::@tag_size, @unused_flag::@unused_flags_size, _::binary>> =
          encoded_header
      ) do
    # TODO header size is being calculated by getting pof and flags??? Should be adjusted
    # header_size = pof_flag * 32 + @header_min_bytes

    # if byte_size(encoded_header) == header_size do
    decode_micro_header_from_binary(encoded_header)
    # else
    #  {:error, "#{__MODULE__}: Malformed header"}
    # end
  end

  defp decode_micro_header_from_binary(
         <<@version::@version_size, @tag::@tag_size, @unused_flag::@unused_flags_size,
           height::@height_size, prev_hash::binary-size(@header_hash_size),
           prev_key_hash::binary-size(@header_hash_size), root_hash::binary-size(@root_hash_size),
           txs_hash::binary-size(@txs_hash_size), time::@time_size, rest::binary>>
       ) do
    # pof_hash_size = pof_tag * @pof_hash_size

    case rest do
      # pof_hash::binary-size(pof_hash_size),
      <<signature::binary-size(@signature_size)>> ->
        {:ok,
         %MicroHeader{
           height: height,
           # pof_hash: pof_hash,
           prev_hash: prev_hash,
           prev_key_hash: prev_key_hash,
           root_hash: root_hash,
           signature: signature,
           txs_hash: txs_hash,
           time: time,
           version: @version
         }}

      _ ->
        {:error, "#{__MODULE__}: Corrupted header data"}
    end
  end

  defp decode_micro_header_from_binary(_) do
    {:error, "#{__MODULE__}: Corrupted header data"}
  end
end
