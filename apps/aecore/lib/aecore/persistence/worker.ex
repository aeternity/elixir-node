defmodule Aecore.Persistence.Worker do
  @moduledoc """
  add/get blocks and chain state to/from disk using rox, the
  elixir rocksdb library - https://hexdocs.pm/rox
  """

  use GenServer

  alias Aecore.Chain.BlockValidation
  alias Aecore.Keys.Worker, as: Keys

  require Logger

  @latest_block_key "latest_block"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ## Client side

  @spec add_block_by_hash(Block.t()) :: :ok | {:error, reason :: term()}
  def add_block_by_hash(%{header: header} = block) do
    hash = BlockValidation.block_header_hash(header)
    GenServer.call(__MODULE__, {:add_block_by_hash, {hash, block}})
  end
  def add_block_by_hash(_block), do: {:error, "bad block structure"}

  @spec get_block_by_hash(String.t()) ::
  {:ok, block :: Block.t()} | :not_found | {:error, reason :: term()}
  def get_block_by_hash(hash) when is_binary(hash) do
    GenServer.call(__MODULE__, {:get_block_by_hash, hash})
  end
  def get_block_by_hash(_hash), do: {:error, "bad hash value"}

  @spec get_all_blocks() ::
  {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_all_blocks() do
    GenServer.call(__MODULE__, :get_all_blocks)
  end

  @spec get_latest_block_height_and_hash() ::
  {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_latest_block_height_and_hash() do
    GenServer.call(__MODULE__, :get_latest_block_height_and_hash)
  end

  @spec add_account_chain_state(account :: binary(), chain_state :: map()) ::
  :ok | {:error, reason :: term()}
  def add_account_chain_state(account, data) do
    GenServer.call(__MODULE__, {:add_account_chain_state, {account, data}})
  end

  @spec get_account_chain_state(account :: binary()) ::
  {:ok, chain_state :: map()} | :not_found | {:error, reason :: term()}
  def get_account_chain_state(account) do
    GenServer.call(__MODULE__, {:get_account_chain_state, account})
  end

  @spec get_all_accounts_chain_states() ::
  {:ok, chain_state :: map()} | :not_found | {:error, reason :: term()}
  def get_all_accounts_chain_states() do
    GenServer.call(__MODULE__, :get_all_accounts_chain_states)
  end

  ## Server side

  def init(_) do
    ## We are ensuring that families for the blocks and chain state
    ## are created. More about them - https://github.com/facebook/rocksdb/wiki/Column-Families
    {:ok, db, %{"blocks_family"       => blocks_family,
                "latest_block_family" => latest_block_family,
                "chain_state_family"  => chain_state_family}} =
      Rox.open(persistence_path(),
        [create_if_missing: true, auto_create_column_families: true],
        ["blocks_family", "latest_block_family", "chain_state_family"])
    {:ok, %{db: db,
            blocks_family: blocks_family,
            latest_block_family: latest_block_family,
            chain_state_family: chain_state_family}}
  end

  def handle_call({:add_block_by_hash, {hash, block}}, _from,
    %{db: _db, latest_block_family: latest_block_family,
      blocks_family: blocks_family} = state) do
    :ok = Rox.put(latest_block_family, @latest_block_key,
      %{hash: hash, height: block.header.height})
    :ok = Rox.put(blocks_family, hash, block)
    {:reply, :ok, state}
  end

  def handle_call({:add_account_chain_state, {account, chain_state}}, _from,
    %{db: _db, chain_state_family: chain_state_family} = state) do
    {:reply, Rox.put(chain_state_family, account, chain_state), state}
  end

  def handle_call({:get_block_by_hash, hash}, _from,
    %{db: _db, blocks_family: blocks_family} = state) do
    {:reply, Rox.get(blocks_family, hash), state}
  end

  def handle_call({:get_account_chain_state, account}, _from,
    %{db: _db, chain_state_family: chain_state_family} = state) do
    {:reply, Rox.get(chain_state_family, account), state}
  end

  def handle_call(:get_all_blocks, _from,
    %{db: _db, blocks_family: blocks_family} = state) do
    all_blocks =
      Rox.stream(blocks_family)
      |> Enum.into(%{})
    {:reply, all_blocks, state}
  end

  def handle_call(:get_latest_block_height_and_hash, _from,
    %{db: _db, latest_block_family: latest_block_family} = state) do
    {:reply, Rox.get(latest_block_family, @latest_block_key), state}
  end

  def handle_call(:get_all_accounts_chain_states, _from,
    %{db: _db, chain_state_family: chain_state_family} = state) do
    chain_state =
      Rox.stream(chain_state_family)
      |> Enum.into(%{})
    {:reply, chain_state, state}
  end

  defp persistence_path(), do: Application.get_env(:aecore, :persistence)[:path]

end
