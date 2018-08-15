defmodule GetTxsForAddressTest do
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account
  alias Aecore.Account.Tx.SpendTx, as: SpendTx
  alias Aecore.Keys
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.Serialization

  setup do
    on_exit(fn ->
      Persistence.delete_all()
      Chain.clear_state()
      :ok
    end)

    []
  end

  @tag timeout: 20_000
  test "get txs for given address test" do
    :ok = Miner.mine_sync_block_to_chain()

    sender_pub = Keys.sign_pubkey()
    sender_priv = Keys.sign_privkey()

    %{public: receiver} = :enacl.sign_keypair()

    {:ok, signed_tx} = Account.spend(sender_pub, sender_priv, receiver, 2, 1, 2, <<"payload">>)

    assert :ok = Pool.add_transaction(signed_tx)

    :ok = Miner.mine_sync_block_to_chain()

    assert 2 <= :erlang.length(Chain.longest_blocks_chain())
    assert 1 == :erlang.length(Pool.get_txs_for_address(receiver))
  end

  @tag timeout: 20_000
  test "get txs for given address with proof test" do
    :ok = Miner.mine_sync_block_to_chain()
    address = Keys.sign_pubkey()
    user_txs = Pool.get_txs_for_address(address)
    user_txs_with_proof = Pool.add_proof_to_txs(user_txs)

    for user_tx_with_proof <- user_txs_with_proof do
      # For some reason this is never executed
      assert false

      transaction =
        user_tx_with_proof
        |> Map.delete(:txs_hash)
        |> Map.delete(:block_hash)
        |> Map.delete(:block_height)
        |> Map.delete(:signature)
        |> Map.delete(:proof)
        |> SpendTx.new()

      key = SignedTx.hash_tx(transaction)
      transaction_bin = SignedTx.rlp_encode(transaction)
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
