defmodule Aecore.Util.Header do
  @moduledoc """
  Header utilities
  """
  alias Aecore.Chain.KeyHeader
  alias Aecore.Chain.MicroHeader
  alias Aeutil.Hash

  @spec hash(KeyHeader.t() | MicroHeader.t()) :: binary()
  def hash(%KeyHeader{} = header) do
    binary = KeyHeader.encode_to_binary(header)
    Hash.hash(binary)
  end

  def hash(%MicroHeader{} = header) do
    binary = MicroHeader.encode_to_binary(header)
    Hash.hash(binary)
  end

  @spec top_key_block_hash(KeyHeader.t() | MicroHeader.t()) :: binary()
  def top_key_block_hash(%KeyHeader{} = header) do
    hash(header)
  end

  def top_key_block_hash(%MicroHeader{prev_key_hash: prev_key_hash}) do
    prev_key_hash
  end
end
