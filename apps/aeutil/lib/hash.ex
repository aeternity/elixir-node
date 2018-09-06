defmodule Aeutil.Hash do
  @moduledoc """
  Module containing hashing functions
  """

  @hash_bytes_size 32

  @spec get_hash_bytes_size :: non_neg_integer()
  def get_hash_bytes_size, do: @hash_bytes_size

  @spec hash_blake2b(binary()) :: binary()
  def hash_blake2b(data) when is_binary(data) do
    {:ok, hash} = :enacl.generichash(@hash_bytes_size, data)
    hash
  end

  @spec hash_sha3(binary()) :: binary()
  def hash_sha3(data) when is_binary(data) do
    :sha3.hash(@hash_bytes_size * 8, data)
  end

  @spec hash_sha256(binary()) :: binary()
  def hash_sha256(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
  end

  @spec hash(binary()) :: binary()
  defdelegate hash(opts), to: __MODULE__, as: :hash_blake2b
end
