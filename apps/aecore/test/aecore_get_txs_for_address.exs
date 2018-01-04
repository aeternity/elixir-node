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
  alias Aecore.Chain.BlockValidation, as: BlockValidation
  alias Aecore.Txs.Pool.Worker, as: Pool


  @tag timeout: 100_000
  test "get txs for given address test" do
    Miner.resume()
    Miner.suspend()

    {:ok, from_acc} = Keys.pubkey()

    to_acc = <<4, 113, 73, 130, 150, 200, 126, 80, 231, 110, 11, 224, 246, 121, 247, 201,
      166, 210, 85, 162, 163, 45, 147, 212, 141, 68, 28, 179, 91, 161, 139, 237,
      168, 61, 115, 74, 188, 140, 143, 160, 232, 230, 187, 220, 17, 24, 249, 202,
      222, 19, 20, 136, 175, 241, 203, 82, 23, 76, 218, 9, 72, 42, 11, 123, 127>>


  nonce = Map.get(Chain.chain_state, from_acc, %{nonce: 0}).nonce + 1
    {:ok, tx1} = Keys.sign_tx(to_acc, 90, nonce, 5)

    assert :ok = Pool.add_transaction(tx1)

    Miner.resume()
    Miner.suspend()

    assert 2 <= :erlang.length(Chain.longest_blocks_chain())
    assert 1 == :erlang.length(Pool.get_txs_for_address(to_acc))
  end

  test "get txs for given address with proof test" do
    Miner.resume()
    Miner.suspend()
    {:ok, address} = Keys.pubkey
    user_txs = Pool.get_txs_for_address(address)
    user_txs_with_proof = Pool.add_proof_to_txs(user_txs)
    for user_tx_with_proof <- user_txs_with_proof do
      transaction = :erlang.term_to_binary(
        user_tx_with_proof
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> TxData.new()
      )
      key = TxData.hash_tx(transaction)
      tx_block = Pool.get_block_by_txs_hash(user_tx_with_proof.txs_hash)
      merkle_tree = BlockValidation.build_merkle_tree(tx_block.txs)
      merkle_proof = :gb_merkle_trees.merkle_proof(key, merkle_tree)

      assert {:ok, :verified} =
        :gb_merkle_trees.verify_merkle_proof(key,
          transaction,
          user_tx_with_proof.txs_hash,
          merkle_proof)
    end
  end
end
