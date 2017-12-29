defmodule Aecore.Persistence.Worker do
  @moduledoc """
  add/get blocks and chain state to/from disk using rox, the
  elixir rocksdb library - https://hexdocs.pm/rox
  """

  use GenServer

  alias Aecore.Chain.BlockValidation

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ## Client side

  @spec write_block_by_hash(block :: map) :: :ok | {:error, reason :: term()}
  def write_block_by_hash(%{header: header} = block) do
    hash = BlockValidation.block_header_hash(header)
    GenServer.call(__MODULE__, {:write_block_by_hash, {hash, block}})
  end
  def write_block_by_hash(_block), do: {:error, "bad block structure"}

  @spec read_block_by_hash(String.t()) ::
  {:ok, block :: map} | :not_found | {:error, reason :: term()}
  def read_block_by_hash(hash) when is_binary(hash) do
    GenServer.call(__MODULE__, {:read_block_by_hash, hash})
  end
  def read_block_by_hash(_hash), do: {:error, "bad hash value"}

  ## Server side

  def init(_) do
    ## We are creating `blocks_by_hash` family for the blocks
    ## https://github.com/facebook/rocksdb/wiki/Column-Families
    {:ok, db, %{"blocks_by_hash" => blocks_family}} =
      Rox.open(persistence_path(),
        [create_if_missing: true, auto_create_column_families: true], ["blocks_by_hash"])
    {:ok, %{db: db, blocks_family: blocks_family}}
  end

  def handle_call({:write_block_by_hash, {hash, block}}, _from,
    %{db: _db, blocks_family: blocks_family} = state) do
    {:reply, Rox.put(blocks_family, hash, block), state}
  end

  def handle_call({:read_block_by_hash, hash}, _from,
    %{db: _db, blocks_family: blocks_family} = state) do
    {:reply, Rox.get(blocks_family, hash), state}
  end

  defp persistence_path(), do: Application.get_env(:aecore, :persistence)[:path]

end
