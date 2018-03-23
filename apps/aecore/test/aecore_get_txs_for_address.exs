defmodule GetTxsForAddressTest do
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx, as: SpendTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.BlockValidation, as: BlockValidation
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Serialization

  setup do
    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    []
  end

  @tag timeout: 20_000
  test "get txs for given address test", setup do
    :ok = Miner.mine_sync_block_to_chain()

    {:ok, sender} = Keys.pubkey()

    receiver =
      <<4, 113, 73, 130, 150, 200, 126, 80, 231, 110, 11, 224, 246, 121, 247, 201, 166, 210, 85,
        162, 163, 45, 147, 212, 141, 68, 28, 179, 91, 161, 139, 237, 168, 61, 115, 74, 188, 140,
        143, 160, 232, 230, 187, 220, 17, 24, 249, 202, 222, 19, 20, 136, 175, 241, 203, 82, 23,
        76, 218, 9, 72, 42, 11, 123, 127>>

    nonce = Map.get(Chain.chain_state(), sender, %{nonce: 0}).nonce + 1
    {:ok, tx1} = Keys.sign_tx(receiver, 90, nonce, 5)

    assert :ok = Pool.add_transaction(tx1)

    :ok = Miner.mine_sync_block_to_chain()

    assert 2 <= :erlang.length(Chain.longest_blocks_chain())
    assert 1 == :erlang.length(Pool.get_txs_for_address(receiver))
  end

  @tag timeout: 20_000
  test "get txs for given address with proof test", setup do
    :ok = Miner.mine_sync_block_to_chain()
    {:ok, address} = Keys.pubkey()
    user_txs = Pool.get_txs_for_address(address)
    user_txs_with_proof = Pool.add_proof_to_txs(user_txs)

    for user_tx_with_proof <- user_txs_with_proof do
      transaction =
        user_tx_with_proof
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> Map.delete(:proof)
        |> SpendTx.new()

      key = SignedTx.hash_tx(transaction)
      transaction_bin = Serialization.pack_binary(transaction)
      tx_block = Chain.get_block(user_tx_with_proof.block_hash)

      assert {:ok, :verified} =
               :gb_merkle_trees.verify_merkle_proof(
                 key,
                 transaction_bin,
                 tx_block.header.txs_hash,
                 user_tx_with_proof.proof
               )
    end
  end
end
