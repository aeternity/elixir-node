defmodule Aecore.Txs.Pool.Worker do
  @moduledoc """
  Module for working with the transaction pool.
  The pool itself is a map with an empty initial state.
  """

  use GenServer

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Block
  alias Aecore.Structures.SpendTx
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Bits
  alias Aehttpserver.Web.Notify

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(initial_pool) do
    {:ok, initial_pool}
  end

  @spec add_transaction(SignedTx.t()) :: :ok | :error
  def add_transaction(tx) do
    GenServer.call(__MODULE__, {:add_transaction, tx})
  end

  @spec remove_transaction(SignedTx.t()) :: :ok
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

  ## Server side

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
      !SignedTx.is_valid?(tx) ->
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
          # Broadcasting notifications for new transaction in a pool(per account and every)
          Notify.broadcast_new_transaction_in_the_pool(tx)
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

  @doc """
  A function that adds a merkle proof for every single transaction
  """

  @spec add_proof_to_txs(list()) :: list()
  def add_proof_to_txs(user_txs) do
    for tx <- user_txs do
      block = Chain.get_block(tx.block_hash)
      tree = BlockValidation.build_merkle_tree(block.txs)
      key =
        tx
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> SpendTx.new()
        |> SpendTx.hash_tx()
      merkle_proof = :gb_merkle_trees.merkle_proof(key, tree)
      Map.put_new(tx, :proof, merkle_proof)
    end
  end

  ## Private functions

  @spec split_blocks(list(Block.t()), String.t(), list()) :: list()
  defp split_blocks([block | blocks], address, txs) do
    user_txs = check_address_tx(block.txs, address, txs)
    if user_txs == [] do
      split_blocks(blocks, address, txs)
    else
      new_txs =
      for block_user_txs <- user_txs do
        block_user_txs
        |>  Map.put_new(:txs_hash, block.header.txs_hash)
        |>  Map.put_new(:block_hash, BlockValidation.block_header_hash(block.header))
        |>  Map.put_new(:block_height, block.header.height)
      end
      split_blocks(blocks, address, new_txs)
    end

  end

  defp split_blocks([], _address, txs) do
    txs
  end

  @spec check_address_tx(list(SignedTx.t()), String.t(), list()) :: list()
  defp check_address_tx([tx | txs], address, user_txs) do
    user_txs =
    if tx.data.from_acc == address or tx.data.to_acc == address  do
      [
        Map.from_struct(tx.data)
        |> Map.put_new(:signature, tx.signature)| user_txs]
    else
      []
    end
    check_address_tx(txs, address, user_txs)
  end

  defp check_address_tx([], _address, user_txs) do
    user_txs
  end
end
