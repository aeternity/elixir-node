defmodule Aecore.Persistence.Worker do
  @moduledoc """
  add/get blocks and chain state to/from disk using rox, the
  elixir rocksdb library - https://hexdocs.pm/rox
  """

  use GenServer

  alias Aecore.Chain.{Block, Header, Target}
  alias Aeutil.Scientific
  alias Rox.Batch

  @typedoc """
  To operate with a patricia merkle tree
  we do need db reference

  Those names referes to the keys into patricia_families
  map in our state
  """

  @type db_ref_name ::
          :proof
          | :txs
          | :accounts
          | :oracles
          | :oracles_cache
          | :naming
          | :channels
          | :contracts
          | :calls

  require Logger

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Every key that it takes is a task type and
  every value is the data that we want to persist
  The purpose of this function is to write many tasks to disk once
  """
  @spec batch_write(map()) :: :ok
  def batch_write(operations) do
    GenServer.call(__MODULE__, {:batch_write, operations})
  end

  def add_block_info(%{block: block, header: header} = info) do
    hash = Header.hash(header)
    GenServer.call(__MODULE__, {:add_block_by_hash, {hash, block}})

    cleaned_info =
      info
      |> Map.delete("block")
      |> Map.delete("chain_state")

    GenServer.call(__MODULE__, {:add_block_info, {hash, cleaned_info}})
  end

  @spec add_block_by_hash(binary(), Block.t()) :: :ok | {:error, reason :: term()}
  def add_block_by_hash(hash, block) do
    GenServer.call(__MODULE__, {:add_block_by_hash, {hash, block}})
  end

  @spec add_block_by_hash(Block.t()) :: :ok | {:error, reason :: term()}
  def add_block_by_hash(%{header: header} = block) do
    hash = Header.hash(header)
    GenServer.call(__MODULE__, {:add_block_by_hash, {hash, block}})
  end

  def add_block_by_hash(block),
    do: {:error, "#{__MODULE__}: Bad block structure: #{inspect(block)}"}

  @spec add_total_difficulty(non_neg_integer()) :: :ok | {:error, reason :: term()}
  def add_total_difficulty(total_difficulty) do
    GenServer.call(__MODULE__, {:add_total_difficulty, total_difficulty})
  end

  @spec get_block_by_hash(String.t()) ::
          {:ok, block :: Block.t()} | :not_found | {:error, reason :: term()}
  def get_block_by_hash(hash) when is_binary(hash) do
    GenServer.call(__MODULE__, {:get_block_by_hash, hash})
  end

  def get_block_by_hash(hash), do: {:error, "#{__MODULE__}: Bad hash value: #{inspect(hash)}"}

  @doc """
  Retrieving last 'num' blocks from db. If have less than 'num' blocks,
  then we will retrieve all blocks. The 'num' must be integer and greater
  than one
  """
  @spec get_blocks(non_neg_integer()) :: {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_blocks(num) do
    GenServer.call(__MODULE__, {:get_blocks, num})
  end

  @spec get_all_blocks() :: {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_all_blocks do
    GenServer.call(__MODULE__, :get_all_blocks)
  end

  @spec get_latest_block_height_and_hash() ::
          {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_latest_block_height_and_hash do
    GenServer.call(__MODULE__, :get_latest_block_height_and_hash)
  end

  @spec update_latest_block_height_and_hash(binary(), non_neg_integer()) ::
          {:ok, map()} | :not_found | {:error, reason :: term()}
  def update_latest_block_height_and_hash(hash, height) do
    GenServer.call(
      __MODULE__,
      {:update_latest_block_height_and_hash, hash, height}
    )
  end

  @spec add_account_chain_state(account :: binary(), chain_state :: map()) ::
          :ok | {:error, reason :: term()}
  def add_account_chain_state(account, data) do
    GenServer.call(__MODULE__, {:add_account_chain_state, {account, data}})
  end

  @spec get_all_chainstates(binary()) ::
          {:ok, chain_state :: map()} | :not_found | {:error, reason :: term()}
  def get_all_chainstates(block_hash) do
    GenServer.call(__MODULE__, {:get_all_chainstates, block_hash})
  end

  @spec get_all_blocks_info() :: {:ok, map()} | :not_found | {:error, reason :: term()}
  def get_all_blocks_info do
    GenServer.call(__MODULE__, :get_all_blocks_info)
  end

  @spec get_total_difficulty() :: non_neg_integer()
  def get_total_difficulty do
    GenServer.call(__MODULE__, :get_total_difficulty)
  end

  @spec delete_all() :: :ok | {:error, any()}
  def delete_all do
    GenServer.call(__MODULE__, :delete_all)
  end

  @doc """
  We need db put handler when we update a patricia tree
  """
  @spec db_handler_put(db_ref_name()) :: function()
  def db_handler_put(db_ref_name) do
    GenServer.call(__MODULE__, {:db_handler, {:put, db_ref_name}})
  end

  @doc """
  We need db get handler when we retrieve a hash from patricia tree
  """
  @spec db_handler_get(db_ref_name()) :: function()
  def db_handler_get(db_ref_name) do
    GenServer.call(__MODULE__, {:db_handler, {:get, db_ref_name}})
  end

  # Server side

  defp all_families do
    [
      "blocks_family",
      "latest_block_info_family",
      "chain_state_family",
      "blocks_info_family",
      "patricia_proof_family",
      "patricia_oracles_family",
      "patricia_oracles_cache_family",
      "patricia_txs_family",
      "patricia_account_family",
      "patricia_naming_family",
      "total_difficulty_family",
      "patricia_channels_family",
      "patricia_contracts_family",
      "patricia_calls_family"
    ]
  end

  def init(_) do
    # We are ensuring that families for the blocks and chain state
    # are created. More about them -
    # https://github.com/facebook/rocksdb/wiki/Column-Families
    {:ok, db,
     %{
       "blocks_family" => blocks_family,
       "latest_block_info_family" => latest_block_info_family,
       "chain_state_family" => chain_state_family,
       "blocks_info_family" => blocks_info_family,
       "patricia_proof_family" => patricia_proof_family,
       "patricia_oracles_family" => patricia_oracles_family,
       "patricia_oracles_cache_family" => patricia_oracles_cache_family,
       "patricia_txs_family" => patricia_txs_family,
       "patricia_account_family" => patricia_accounts_family,
       "patricia_naming_family" => patricia_naming_family,
       "total_difficulty_family" => total_difficulty_family,
       "patricia_channels_family" => patricia_channels_family,
       "patricia_contracts_family" => patricia_contracts_family,
       "patricia_calls_family" => patricia_calls_family
     } = families_map} =
      Rox.open(
        persistence_path(),
        [create_if_missing: true, auto_create_column_families: true],
        all_families()
      )

    {:ok,
     %{
       db: db,
       families_map: families_map,
       blocks_family: blocks_family,
       latest_block_info_family: latest_block_info_family,
       chain_state_family: chain_state_family,
       blocks_info_family: blocks_info_family,
       total_difficulty_family: total_difficulty_family,
       patricia_families: %{
         proof: patricia_proof_family,
         accounts: patricia_accounts_family,
         oracles: patricia_oracles_family,
         oracles_cache: patricia_oracles_cache_family,
         txs: patricia_txs_family,
         test_trie: db,
         naming: patricia_naming_family,
         channels: patricia_channels_family,
         contracts: patricia_contracts_family,
         calls: patricia_calls_family
       }
     }}
  end

  def handle_call(
        {:batch_write, operations},
        _from,
        %{
          db: db,
          blocks_family: blocks_family,
          chain_state_family: chain_state_family,
          latest_block_info_family: latest_block_info_family,
          blocks_info_family: blocks_info_family,
          total_difficulty_family: total_difficulty_family
        } = state
      ) do
    batch =
      Enum.reduce(operations, Batch.new(), fn {type, data}, batch_acc ->
        family =
          case type do
            :chain_state -> chain_state_family
            :block -> blocks_family
            :latest_block_info -> latest_block_info_family
            :block_info -> blocks_info_family
            :total_diff -> total_difficulty_family
          end

        Enum.reduce(data, batch_acc, fn {key, val}, batch_acc_ ->
          Batch.put(batch_acc_, family, to_string(key), val)
        end)
      end)

    Batch.write(batch, db)
    {:reply, :ok, state}
  end

  def handle_call(
        {:add_block_by_hash, {hash, block}},
        _from,
        %{blocks_family: blocks_family} = state
      ) do
    {:reply, Rox.put(blocks_family, hash, block, write_options()), state}
  end

  def handle_call(
        {:add_block_info, {hash, info}},
        _from,
        %{blocks_info_family: blocks_info_family} = state
      ) do
    {:reply, Rox.put(blocks_info_family, hash, info, write_options()), state}
  end

  def handle_call(
        {:add_account_chain_state, {account, chain_state}},
        _from,
        %{chain_state_family: chain_state_family} = state
      ) do
    {:reply, Rox.put(chain_state_family, account, chain_state, write_options()), state}
  end

  def handle_call(
        {:add_total_difficulty, new_total_difficulty},
        _from,
        %{total_difficulty_family: total_diff_family} = state
      ) do
    key = "total_difficulty"
    {:reply, Rox.put(total_diff_family, key, new_total_difficulty, write_options()), state}
  end

  def handle_call(
        {:get_block_by_hash, block_hash},
        _from,
        %{blocks_family: blocks_family} = state
      ) do
    case Rox.get(blocks_family, block_hash) do
      {:ok, _block} = data -> {:reply, data, state}
      _ -> {:reply, {:error, "Can't find block for hash: #{inspect(block_hash)}"}, state}
    end
  end

  def handle_call({:get_blocks, blocks_num}, _from, state)
      when blocks_num < 1 do
    {:reply, "Blocks number must be greater than one", state}
  end

  def handle_call({:get_blocks, blocks_num}, _from, %{blocks_family: blocks_family} = state) do
    max_blocks_height = Rox.count(blocks_family)
    threshold = max_blocks_height - blocks_num

    last_blocks =
      if threshold < 0 do
        blocks_family
        |> Rox.stream()
        |> Enum.into([])
      else
        blocks_family
        |> Rox.stream()
        |> Enum.reduce([], fn {_hash, %{header: %{height: height}}} = record, acc ->
          if threshold <= height do
            [record | acc]
          else
            acc
          end
        end)
      end

    {:reply, Enum.into(last_blocks, %{}), state}
  end

  def handle_call(:get_all_blocks, _from, %{blocks_family: blocks_family} = state) do
    all_blocks =
      blocks_family
      |> Rox.stream()
      |> Enum.into(%{})

    {:reply, all_blocks, state}
  end

  def handle_call(:get_all_blocks_info, _from, %{blocks_info_family: blocks_info_family} = state) do
    all_blocks_info =
      blocks_info_family
      |> Rox.stream()
      |> Enum.into(%{})

    {:reply, all_blocks_info, state}
  end

  def handle_call(
        :get_total_difficulty,
        _from,
        %{total_difficulty_family: total_diff_family} = state
      ) do
    response = Rox.get(total_diff_family, "total_difficulty")

    total_diff =
      case response do
        {:ok, total_difficulty} ->
          total_difficulty

        _ ->
          Scientific.target_to_difficulty(Target.highest_target_scientific())
      end

    {:reply, total_diff, state}
  end

  def handle_call(:delete_all, _from, %{db: db, families_map: families_map} = state) do
    status =
      families_map
      |> Map.values()
      |> Enum.reduce(Batch.new(), fn family, batch_acc ->
        family
        |> Rox.stream()
        |> Enum.reduce(batch_acc, fn {key, _}, batch_acc ->
          Batch.delete(batch_acc, family, key)
        end)
      end)
      |> Batch.write(db)

    {:reply, status, state}
  end

  def handle_call(
        {:get_all_chainstates, block_hash},
        _from,
        %{chain_state_family: chain_state_family} = state
      ) do
    case Rox.get(chain_state_family, block_hash) do
      {:ok, _chainstate} = data -> {:reply, data, state}
      _ -> {:reply, {:error, "Can't find chainstate for hash: #{inspect(block_hash)}"}, state}
    end
  end

  def handle_call(
        :get_latest_block_height_and_hash,
        _from,
        %{latest_block_info_family: latest_block_info_family} = state
      ) do
    hash = Rox.get(latest_block_info_family, "top_hash")
    height = Rox.get(latest_block_info_family, "top_height")

    reply =
      case hash == :not_found or height == :not_found do
        true -> :not_found
        _ -> {:ok, %{hash: elem(hash, 1), height: elem(height, 1)}}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:update_latest_block_height_and_hash, hash, height},
        _from,
        %{latest_block_info_family: latest_block_info_family} = state
      ) do
    :ok = Rox.put(latest_block_info_family, "top_hash", hash, write_options())

    :ok = Rox.put(latest_block_info_family, "top_height", height, write_options())

    {:reply, :ok, state}
  end

  def handle_call({:db_handler, {type, db_ref_name}}, _from, state) when is_atom(db_ref_name) do
    db_ref = state.patricia_families[db_ref_name]

    handler =
      case type do
        :put ->
          fn key, val -> Rox.put(db_ref, key, val) end

        :get ->
          fn key -> Rox.get(db_ref, key) end
      end

    {:reply, handler, state}
  end

  defp persistence_path, do: Application.app_dir(:aecore, "priv") <> Application.get_env(:aecore, :persistence)[:path]

  defp write_options, do: Application.get_env(:aecore, :persistence)[:write_options]
end
