defmodule Aecore.Util.Header do
  @moduledoc """
  Header utilities
  """
  alias Aecore.Chain.KeyHeader
  alias Aecore.Chain.MicroHeader

  @spec hash(KeyHeader.t() | MicroHeader.t()) :: binary()
  def hash(header) do
    case header do
      %KeyHeader{} ->
        KeyHeader.hash(header)

      %MicroHeader{} ->
        MicroHeader.hash(header)
    end
  end

  @spec top_key_block_hash(KeyHeader.t() | MicroHeader.t()) :: binary()
  def top_key_block_hash(prev_header) do
    case prev_header do
      %KeyHeader{} ->
        hash(prev_header)

      %MicroHeader{prev_key_hash: prev_key_hash} ->
        prev_key_hash
    end
  end
end
