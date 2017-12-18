defmodule GetTxsForAddressTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.ChainState, as: ChainState
  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.TxData, as: TxData
  alias Aecore.Structures.SignedTx, as: SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.Header, as: Header
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Utils.Blockchain.BlockValidation, as: BlockValidation
  alias Aecore.Txs.Pool.Worker, as: Pool


  @tag timeout: 100_000
  test "get txs for given address test" do
    {:ok, address} = Keys.pubkey()

    ## Create unique address
    address_hex =
      address
      |> Base.encode16()
      |> String.slice(1, String.length(Base.encode16(address)))
      |> Kernel.<> "1"
    address_bin = address_hex |> Base.decode16!()
    user_pubkey = {:ok, address_bin}

    {:ok, tx1} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5, 1, 1)
    {:ok, tx2} = Keys.sign_tx(elem(user_pubkey, 1), 7, 1, 1)
    {:ok, tx3} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5, 1, 1)

    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx2)
    assert :ok = Pool.add_transaction(tx3)
    Miner.resume()
    Miner.suspend()

    assert 2 <= :erlang.length(Chain.all_blocks)
    assert [tx2] = Pool.get_txs_for_address(address_bin)
  end

  test "get txs for given address with proof test" do
    Miner.resume()
    Miner.suspend()
    {:ok, address} = Keys.pubkey
    user_txs = Pool.get_txs_for_address(address)
    user_txs_with_proof = Pool.get_txs_for_address_with_proof(user_txs)
    for user_tx_with_proof <- user_txs_with_proof do
      transaction = :erlang.term_to_binary(
        tx
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> TxData.new()
      )
      key = :crypto.hash(:sha256, transaction)
      assert {:ok, :verified} =
        :gb_merkle_trees.verify_merkle_proof(key,
          transaction,
          user_tx_with_proof.txs_hash,
          user_tx_with_proof.proof)
    end
  end
