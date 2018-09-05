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
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
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
end
