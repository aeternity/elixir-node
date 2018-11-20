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

  defp flags do
    <<@tag::@tag_size, @unused_flag::@unused_flags_size>>
  end
end
