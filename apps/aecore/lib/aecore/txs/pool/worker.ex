defmodule Aecore.Txs.Pool.Worker do
  @moduledoc """
  Module for working with the transaction pool.
  The pool itself is a map with an empty initial state.
  """

  use GenServer

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Block
  alias Aecore.Structures.TxData
  alias Aecore.Chain.BlockValidation
  alias Aeutil.Serialization
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Bits

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


  @spec get_txs_for_address(String.t()) :: list()
  def get_txs_for_address(address) do
    GenServer.call(__MODULE__, {:get_txs_for_address, address})
  end

  @spec get_block_by_txs_hash(binary()) :: %Block{}
  def get_block_by_txs_hash(txs_hash) do
    GenServer.call(__MODULE__, {:get_block_by_txs_hash, txs_hash})
  end


  ## Server side

  def handle_call({:get_block_by_txs_hash, txs_hash}, _from, state) do
    case Enum.find(Chain.longest_blocks_chain(), fn block ->
          block.header.txs_hash == txs_hash end) do
      block ->
        {:reply, block, state}
      nil ->
        {:reply, {:error, "Block not found!"}, state}
    end
  end

  def handle_call({:get_txs_for_address, address}, _from, state) do
    txs_list = split_blocks(Chain.longest_blocks_chain(), address, [])
    {:reply, txs_list, state}
  end

  def handle_call({:add_transaction, tx}, _from, tx_pool) do
    tx_size_bits = tx |> :erlang.term_to_binary() |> Bits.extract() |> Enum.count()
    tx_size_bytes = tx_size_bits / 8
    is_minimum_fee_met =
      tx.data.fee >= Float.floor(tx_size_bytes /
      Application.get_env(:aecore, :tx_data)[:pool_fee_bytes_per_token])

    cond do
      !SignedTx.is_valid(tx) ->
        Logger.error("Invalid transaction")
        {:reply, :error, tx_pool}
      !is_minimum_fee_met ->
        Logger.error("Fee is too low")
        {:reply, :error, tx_pool}
      true ->
        updated_pool = Map.put_new(tx_pool, :crypto.hash(:sha256, :erlang.term_to_binary(tx)), tx)
        if tx_pool == updated_pool do
          Logger.info("Transaction is already in pool")
        else
          Peers.broadcast_tx(tx)
        end
        {:reply, :ok, updated_pool}
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

  def add_proof_to_txs(user_txs) do
    blocks_for_user_txs =
    for user_tx <- user_txs do
      get_block_by_txs_hash(user_tx.txs_hash)
    end
    merkle_trees =
    for block <- blocks_for_user_txs do
      BlockValidation.build_merkle_tree(block.txs)
    end
    user_txs_trees = Enum.zip(user_txs, merkle_trees)
    proof =
    for user_tx_tree <- user_txs_trees  do
      {tx, tree} = user_tx_tree
      key = :erlang.term_to_binary(
        tx
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> TxData.new()
      )
      |> TxData.hash_tx()
      merkle_proof = :gb_merkle_trees.merkle_proof(key, tree)
      serialized_merkle_proof = serialize_merkle_proof(merkle_proof, [])
      Map.put_new(tx, :proof, serialized_merkle_proof)
    end
  end

  ## Private functions

  defp split_blocks([block | blocks], address, txs) do
    user_txs = check_address_tx(block.txs, address, txs)
    case user_txs do
      [] -> split_blocks(blocks, address, user_txs)
      _ ->
        block_user_txs =
      for block_user_txs <- user_txs do
        block_user_txs
        |>  Map.put_new(:txs_hash, block.header.txs_hash)
        |>  Map.put_new(:block_hash, block.header.chain_state_hash)
        |>  Map.put_new(:block_height, block.header.height)
      end
        split_blocks(blocks, address, block_user_txs)
    end
  end

  defp split_blocks([], address, txs) do
    txs
  end

  defp check_address_tx([tx | txs], address, user_txs) do
    if tx.data.from_acc == address or tx.data.to_acc == address  do
      user_txs = [
        Map.from_struct(tx.data)
        |> Map.put_new(:signature, tx.signature)| user_txs]
    end

    check_address_tx(txs, address, user_txs)
  end
  defp check_address_tx([], address, user_txs) do
    user_txs
  end

  defp serialize_merkle_proof(proof, acc) when is_tuple(proof) do
    proof
    |> Tuple.to_list()
    |> serialize_merkle_proof(acc)
  end
  defp serialize_merkle_proof([], acc), do: acc
  defp serialize_merkle_proof([head | tail], acc) do
    if is_tuple(head) do
      serialize_merkle_proof(Tuple.to_list(head), acc)
    else
      acc = [Serialization.hex_binary(head, :serialize)| acc]
      serialize_merkle_proof(tail, acc)
    end
  end
end
