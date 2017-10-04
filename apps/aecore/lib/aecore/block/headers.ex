defmodule Aecore.Block.Headers do
  @moduledoc """
  This module is handling all operation
  in the headers context
  """
  alias Aecore.Structures.Header

  @spec prev_hash(Header.header()) :: binary()
  def prev_hash(%Header{prev_hash: prev_hash}=header) do
    prev_hash
  end

  @spec difficulty(Header.header()) :: integer()
  def difficulty(%Header{difficulty_target: difficulty}=header) do
    difficulty
  end

  @spec set_difficulty(Header.header(), integer()) :: Header.header()
  def set_difficulty(%Header{}=header, new_difficulty) do
    %{header | difficulty_target: new_difficulty}
  end

  @spec timestamp(Header.header()) :: integer()
  def timestamp(%Header{timestamp: timestamp}=header) do
    timestamp
  end

  @spec set_timestamp(Header.header(), integer()) :: Header.header()
  def set_timestamp(%Header{}=header, new_timestamp) do
    %{header | timestamp: new_timestamp}
  end

  @spec height(Header.header()) :: integer()
  def height(%Header{height: height}=header) do
    height
  end

  @spec increment_height(Header.header()) :: Header.header()
  def increment_height(%Header{height: height}=header) do
    %{header | height: height + 1}
  end

  @spec difficulty(Header.header()) :: integer()
  def difficulty(%Header{difficulty_target: difficulty}=header) do
    difficulty
  end

  @spec set_nonce(Header.header(), integer()) :: integer()
  def set_nonce(%Header{}=header, nonce) do
    %{header | nonce: nonce}
  end

  @spec increment_nonce(Header.header()) :: Header.header()
  def increment_nonce(%Header{nonce: nonce}=header) do
    %{header | nonce: nonce + 1}
  end

  @spec txs_hash(Header.header()) :: binary()
  def txs_hash(%Header{txs_hash: txs_hash}=header) do
    txs_hash
  end

  @spec new(integer(), binary(), binary(), integer(),integer(),integer())
  :: Header.header()
  def new(height,
          prev_hash,
          txs_hash,
          difficulty,
          nonce,
          version) do
    %{Header.create
      | height: height,
        prev_hash: prev_hash,
        txs_hash: txs_hash,
        timestamp: System.system_time(:milliseconds),
        nonce: nonce,
        version: version,
        difficulty_target: difficulty}
  end

  @spec serialize_header(Header.header()) :: binary()
  def serialize_header(%Header{}=header) do
    :erlang.term_to_binary(header)
  end

  @spec deserialize_header(binary()) :: Header.header()
  def deserialize_header(header_bin) do
    :erlang.binary_to_term(header_bin)
  end

end
