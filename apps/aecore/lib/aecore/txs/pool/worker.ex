defmodule Aecore.Txs.Pool.Worker do
  @moduledoc """
  Module for working with the transaction pool.
  The pool itself is a map with an empty initial state.
  """

  use GenServer

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(initial_pool) do
    {:ok, initial_pool}
  end


  ## Client side

  @spec add_transaction(%SignedTx{}) :: :ok | :error
  def add_transaction(tx) do
    GenServer.call(__MODULE__, {:add_transaction, tx})
  end

  @spec remove_transaction(%SignedTx{}) :: :ok
  def remove_transaction(tx) do
    GenServer.call(__MODULE__, {:remove_transaction, tx})
  end

  @spec get_pool() :: map()
  def get_pool() do
    GenServer.call(__MODULE__, :get_pool)
  end

  @spec get_and_empty_pool() :: map()
  def get_and_empty_pool() do
    GenServer.call(__MODULE__, :get_and_empty_pool)
  end


  @spec get_txs_for_address(String.t(), atom()) :: list()
  def get_txs_for_address(address, option) do
    GenServer.call(__MODULE__, {:get_txs_for_address,{address, option}})
  end


  ## Server side

  def handle_call({:get_txs_for_address,{address, option}}, _from, state) do
    txs_list = split_blocks(Chain.all_blocks(), address, [], option)
    {:reply, txs_list, state}
  end

  def handle_call({:add_transaction, tx}, _from, tx_pool) do
    is_tx_valid = Keys.verify(tx.data, tx.signature, tx.data.from_acc)
    if is_tx_valid do
      updated_pool = Map.put_new(tx_pool, :crypto.hash(:sha256, :erlang.term_to_binary(tx)), tx)
      case tx_pool == updated_pool do
        true -> Logger.info(" This transaction already has been added")
        false -> Peers.broadcast_to_all({:new_tx, tx})
      end
      {:reply, :ok, updated_pool}
    else
      {:reply, :error, tx_pool}
    end
  end

  def handle_call({:remove_transaction, tx}, _from, tx_pool) do
    {_, updated_pool} = Map.pop(tx_pool, :crypto.hash(:sha256, :erlang.term_to_binary(tx)))
    {:reply, :ok, updated_pool}
  end

  def handle_call(:get_pool, _from, tx_pool) do
    {:reply, tx_pool, tx_pool}
  end

  def handle_call(:get_and_empty_pool, _from, tx_pool) do
    {:reply, tx_pool, %{}}
  end

  ## Private functions

  defp split_blocks([block | blocks], address, txs, :no_hash ) do
    user_txs = check_address_tx(block.txs, address, txs)
    split_blocks(blocks, address, user_txs, :no_hash)
  end

  defp split_blocks([block | blocks], address, txs, :add_hash) do
    user_txs = check_address_tx(block.txs, address, txs)
    case user_txs do
      [] -> split_blocks(blocks, address, user_txs, :add_hash)
      _ ->
        block_user_txs =
      for block_user_txs <- user_txs do
        Map.put_new(block_user_txs,
          :txs_hash,
          block.header.txs_hash)
      end
        split_blocks(blocks, address, block_user_txs, :add_hash)
    end
  end

  defp split_blocks([], address, txs, _) do
    txs
  end

  defp check_address_tx([tx | txs], address, user_txs) do
    if tx.data.from_acc == address or tx.data.to_acc == address  do
      user_txs = [Map.from_struct(tx.data) | user_txs]
    end

    check_address_tx(txs, address, user_txs)
  end
  defp check_address_tx([], address, user_txs) do
    user_txs
  end

end
