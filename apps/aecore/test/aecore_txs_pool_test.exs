defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Tx.DataTx
  alias Aecore.Keys
  alias Aecore.Account.Account

  setup do
    Code.require_file("test_utils.ex", "./test")
    path = Application.get_env(:aecore, :persistence)[:path]

    if File.exists?(path) do
      File.rm_rf(path)
    end

    Chain.clear_state()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    %{public: b_pub_key} = :enacl.sign_keypair()
    {pubkey, privkey} = Keys.keypair(:sign)

    [
      a_pub_key: pubkey,
      priv_key: privkey,
      b_pub_key: b_pub_key
    ]
  end

  @tag timeout: 20_000
  @tag :txs_pool
  test "add transaction, remove it and get pool", wallet do
    # Empty the pool from the other tests
    Pool.get_and_empty_pool()

    nonce1 = Account.nonce(TestUtils.get_accounts_chainstate(), wallet.a_pub_key) + 1

    {:ok, signed_tx1} =
      Account.spend(
        wallet.a_pub_key,
        wallet.priv_key,
        wallet.b_pub_key,
        5,
        10,
        nonce1,
        <<"payload">>
      )

    {:ok, signed_tx2} =
      Account.spend(
        wallet.a_pub_key,
        wallet.priv_key,
        wallet.b_pub_key,
        5,
        10,
        nonce1 + 1,
        <<"payload">>
      )

    :ok = Miner.mine_sync_block_to_chain()

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
    assert :ok = Pool.remove_transaction(signed_tx2)
    assert Enum.count(Pool.get_pool()) == 1

    :ok = Miner.mine_sync_block_to_chain()
    assert length(Chain.longest_blocks_chain()) > 1
    assert Enum.count(Chain.top_block().txs) == 1
    assert Enum.empty?(Pool.get_pool())
  end

  test "fail negative ammount in  transaction", wallet do
    nonce = Account.nonce(TestUtils.get_accounts_chainstate(), wallet.a_pub_key) + 1

    assert {:error, "Elixir.Aecore.Account.Tx.SpendTx: The amount cannot be a negative number"} =
             DataTx.validate(
               DataTx.init(
                 SpendTx,
                 %{receiver: wallet.b_pub_key, amount: -5, version: 1, payload: <<"payload">>},
                 wallet.a_pub_key,
                 10,
                 nonce
               )
             )
  end
end
