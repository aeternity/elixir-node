defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Pool.start_link([])
    []
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block" do
    {account1, account2, account3} = get_accounts_one_block()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    pubkey = elem(Keys.pubkey(), 1)

    # account A has 100 tokens, spends 99 (+1 fee) to B should succeed
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    {:ok, tx1} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx1)

    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    tx2 = create_signed_tx(account1, account2, 90,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx2)
    :ok =  Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 90 == Chain.chain_state[account2_pub_key].balance

    # account1 => 0; account2 => 90

    # account A has 100 tokens, spends 100 (+10 fee) to B should be invalid
    {:ok, tx3} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx3)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx4 = create_signed_tx(account1, account2, 100,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx4)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state[account1_pub_key].balance

    # acccount1 => 100; account2 => 90

    # account A has 100 tokens, spends 30 (+10 fee) to B, and two times 20 (+10 fee) to C should succeed

    account1_initial_nonce = Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce
    tx5 = create_signed_tx(account1, account2, 30, account1_initial_nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx5)
    tx6 = create_signed_tx(account1, account3, 20, account1_initial_nonce + 2, 10)
    assert :ok = Pool.add_transaction(tx6)
    tx7 = create_signed_tx(account1, account3, 20, account1_initial_nonce + 3, 10)
    assert :ok = Pool.add_transaction(tx7)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 120 == Chain.chain_state[account2_pub_key].balance
    assert 40 == Chain.chain_state[account3_pub_key].balance

    # account1 => 0; account2 => 120; account3 => 40

    # account A has 100 tokens, spends 40 (+10 fee) to B, and two times 20 (+10 fee) to C,
    # last transaction to C should be invalid, others be included
    account1_initial_nonce2 = Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce
    {:ok, tx8} = Keys.sign_tx(account1_pub_key, 100,
                              Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx8)
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    tx9 = create_signed_tx(account1, account2, 40, account1_initial_nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(tx9)
    tx10 = create_signed_tx(account1, account3, 20, account1_initial_nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(tx10)
    tx11 = create_signed_tx(account1, account3, 20, account1_initial_nonce2 + 3, 10)
    assert :ok = Pool.add_transaction(tx11)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state[account1_pub_key].balance
    assert 160 == Chain.chain_state[account2_pub_key].balance
    assert 60 == Chain.chain_state[account3_pub_key].balance

    # account1 => 20; account2 => 160; account3 => 60

    # account C has 100 tokens, spends 90 (+10 fee) to B, B spends 90 (+10 fee) to A should succeed
    {:ok, tx12} = Keys.sign_tx(account3_pub_key, 40,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx12)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx13 = create_signed_tx(account3, account2, 90,
                          Map.get(Chain.chain_state, account3_pub_key, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx13)
    tx14 = create_signed_tx(account2, account1, 90,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx14)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account3_pub_key].balance
    assert 150 == Chain.chain_state[account2_pub_key].balance
    assert 110 == Chain.chain_state[account1_pub_key].balance
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in multiple blocks" do
    {account1, account2, account3} = get_accounts_multiple_blocks()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    pubkey = elem(Keys.pubkey(), 1)

    # account A has 100 tokens, spends 99 (+1 fee) to B should succeed
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    {:ok, tx1} = Keys.sign_tx(account1_pub_key, 100,
      Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx1)
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    tx2 = create_signed_tx(account1, account2, 90,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx2)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 90 == Chain.chain_state[account2_pub_key].balance

    # account1 => 0; account2 => 90

    # account A has 100 tokens, spends 100 (+10 fee) to B should be invalid
    {:ok, tx3} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx3)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx4 = create_signed_tx(account1, account2, 100,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx4)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state[account1_pub_key].balance

    # acccount1 => 100; account2 => 90

    # account A has 100 tokens, spends 30 (+10 fee) to B, and two times 20 (+10 fee) to C should succeed
    tx5 = create_signed_tx(account1, account2, 30,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx5)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx6 = create_signed_tx(account1, account3, 20,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx6)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx7 = create_signed_tx(account1, account3, 20,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx7)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 120 == Chain.chain_state[account2_pub_key].balance
    assert 40 == Chain.chain_state[account3_pub_key].balance

    # account1 => 0; account2 => 120; account3 => 40

    # account A has 100 tokens, spends 40 (+10 fee) to B, and two times 20 (+10 fee) to C,
    # last transaction to C should be invalid, others be included
    {:ok, tx8} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx8)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx9 = create_signed_tx(account1, account2, 40,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx9)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx10 = create_signed_tx(account1, account3, 20,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx10)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx11 = create_signed_tx(account1, account3, 20,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx11)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state[account1_pub_key].balance
    assert 160 == Chain.chain_state[account2_pub_key].balance
    assert 60 == Chain.chain_state[account3_pub_key].balance

    # account1 => 20; account2 => 160; account3 => 60

    # account A has 100 tokens, spends 90 (+10 fee) to B, B spends 90 (+10 fee) to C should succeed
    {:ok, tx12} = Keys.sign_tx(account1_pub_key, 80,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx12)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx13 = create_signed_tx(account1, account2, 90,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx13)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx14 = create_signed_tx(account2, account3, 90,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 10)

    assert :ok = Pool.add_transaction(tx14)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 150 == Chain.chain_state[account2_pub_key].balance
    assert 150 == Chain.chain_state[account3_pub_key].balance
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block, miner collects all the fees from the transactions" do
    {account1, account2, account3} = get_accounts_miner_fees()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    pubkey = elem(Keys.pubkey(), 1)

    :ok = Miner.mine_sync_block_to_chain
    :ok = Miner.mine_sync_block_to_chain
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    {:ok, tx1} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx1)
    {:ok, tx2} = Keys.sign_tx(account2_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 2, 10)
    assert :ok = Pool.add_transaction(tx2)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    tx3 = create_signed_tx(account1, account3, 90,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx3)
    tx4 = create_signed_tx(account2, account3, 90,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 10)
    assert :ok = Pool.add_transaction(tx4)
    miner_balance_before_mining = Map.get(Chain.chain_state, pubkey).balance
    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    miner_balance_after_mining = Map.get(Chain.chain_state, pubkey).balance
    assert miner_balance_after_mining == miner_balance_before_mining + Miner.coinbase_transaction_value() + 20
  end

  test "locked amount" do
    {:ok, pubkey} = Keys.pubkey()
    account1 = get_account_locked_amount()
    {account1_pub_key, _account1_priv_key} = account1

    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()
    {:ok, tx1} = Keys.sign_tx(account1_pub_key, 90,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 10,
                             Chain.top_block().header.height +
                              Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 3)

    Pool.add_transaction(tx1)
    :ok = Miner.mine_sync_block_to_chain
    tx2 = create_signed_tx(account1, {pubkey, <<0>>}, 50,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 10)
    Pool.add_transaction(tx2)
    :ok = Miner.mine_sync_block_to_chain

    assert Enum.count(Pool.get_pool()) == 1
    :ok = Miner.mine_sync_block_to_chain
    assert Enum.count(Pool.get_pool()) == 1
    assert Map.get(Chain.chain_state, account1_pub_key).balance == 90
    miner_balance_before_block = Map.get(Chain.chain_state, pubkey).balance
    :ok = Miner.mine_sync_block_to_chain
    assert Enum.empty?(Pool.get_pool())
    miner_balance_after_block = Map.get(Chain.chain_state, pubkey).balance
    assert miner_balance_after_block == miner_balance_before_block + 100 + 60
  end

  defp get_accounts_one_block() do
    account1 = {
        <<4, 94, 96, 161, 182, 76, 153, 22, 179, 136, 60, 87, 225, 135, 253, 179, 80,
          40, 80, 149, 21, 26, 253, 48, 139, 155, 200, 45, 150, 183, 61, 46, 151, 42,
          245, 199, 168, 60, 121, 39, 180, 82, 162, 173, 86, 194, 180, 54, 116, 190,
          199, 155, 97, 222, 85, 83, 147, 172, 10, 85, 112, 29, 54, 0, 78>>,
        <<214, 90, 19, 166, 30, 35, 31, 96, 16, 116, 48, 33, 26, 76, 192, 195, 104,
          242, 147, 120, 240, 124, 112, 222, 213, 112, 142, 218, 49, 33, 6, 81>>
      }
    account2 = {
        <<4, 205, 231, 80, 153, 60, 210, 201, 30, 39, 4, 191, 92, 231, 80, 143, 98,
          143, 46, 150, 175, 162, 230, 59, 56, 2, 60, 238, 206, 218, 239, 177, 201, 66,
          161, 205, 159, 69, 177, 155, 172, 222, 43, 225, 241, 181, 226, 244, 106, 23,
          114, 161, 65, 121, 146, 35, 27, 136, 15, 142, 228, 22, 217, 78, 90>>,
        <<151, 121, 56, 150, 179, 169, 141, 25, 212, 247, 156, 162, 120, 205, 59, 184,
          49, 201, 75, 67, 170, 113, 157, 114, 129, 149, 206, 62, 182, 239, 146, 26>>
      }
    account3 = {
        <<4, 167, 170, 180, 131, 214, 204, 39, 21, 99, 168, 142, 78, 66, 54, 118, 143,
          18, 28, 73, 62, 255, 220, 172, 4, 166, 255, 54, 72, 39, 34, 233, 23, 124,
          242, 120, 68, 145, 79, 31, 63, 168, 166, 87, 153, 108, 93, 92, 249, 6, 21,
          75, 159, 180, 17, 18, 6, 186, 42, 199, 140, 254, 115, 165, 199>>,
        <<158, 99, 132, 39, 80, 18, 118, 135, 107, 173, 203, 149, 238, 177, 124, 169,
          207, 241, 200, 73, 154, 108, 205, 151, 103, 197, 21, 0, 183, 163, 137, 228>>
      }

      {account1, account2, account3}
  end

  defp get_accounts_multiple_blocks() do
    account1 = {
        <<4, 113, 73, 130, 150, 200, 126, 80, 231, 110, 11, 224, 246, 121, 247, 201,
          166, 210, 85, 162, 163, 45, 147, 212, 141, 68, 28, 179, 91, 161, 139, 237,
          168, 61, 115, 74, 188, 140, 143, 160, 232, 230, 187, 220, 17, 24, 249, 202,
          222, 19, 20, 136, 175, 241, 203, 82, 23, 76, 218, 9, 72, 42, 11, 123, 127>>,
        <<198, 218, 48, 178, 127, 24, 201, 115, 3, 29, 188, 220, 222, 189, 132, 139,
          168, 1, 64, 134, 103, 38, 151, 213, 195, 5, 219, 138, 29, 137, 119, 229>>
      }
    account2 = {
        <<4, 44, 202, 225, 249, 173, 82, 71, 56, 32, 113, 206, 123, 220, 201, 169, 40,
          91, 56, 206, 54, 114, 162, 48, 226, 255, 87, 3, 113, 161, 45, 231, 163, 50,
          116, 30, 204, 109, 69, 255, 54, 78, 238, 249, 34, 139, 9, 35, 99, 246, 181,
          238, 165, 123, 67, 66, 217, 176, 227, 237, 64, 84, 65, 73, 141>>,
        <<44, 81, 132, 144, 204, 94, 98, 172, 51, 110, 175, 30, 195, 124, 217, 172,
          242, 240, 60, 102, 96, 91, 195, 138, 253, 247, 130, 188, 62, 229, 62, 37>>
      }
    account3 = {
        <<4, 11, 38, 199, 95, 205, 49, 85, 168, 55, 88, 105, 244, 159, 57, 125, 71,
          128, 119, 87, 224, 135, 195, 98, 218, 32, 225, 96, 254, 88, 55, 219, 164,
          148, 30, 203, 57, 24, 121, 208, 160, 116, 231, 94, 229, 135, 225, 47, 16,
          162, 250, 63, 103, 111, 249, 66, 67, 21, 133, 54, 152, 61, 119, 51, 188>>,
        <<19, 239, 205, 35, 76, 49, 9, 230, 59, 169, 195, 217, 222, 135, 204, 201, 160,
          126, 253, 20, 230, 122, 184, 193, 131, 53, 157, 50, 117, 29, 195, 47>>
      }

    {account1, account2, account3}
  end

  defp get_accounts_miner_fees() do
    account1 = {
        <<4, 231, 192, 96, 22, 175, 115, 58, 27, 93, 216, 187, 43, 116, 150, 164, 153,
          80, 134, 135, 12, 127, 173, 196, 198, 181, 84, 119, 225, 204, 150, 176, 26,
          119, 103, 128, 201, 93, 131, 7, 169, 48, 28, 60, 16, 112, 65, 8, 46, 212, 32,
          251, 135, 81, 99, 146, 67, 139, 42, 151, 183, 210, 45, 195, 8>>,
        <<129, 187, 237, 185, 104, 21, 152, 221, 22, 1, 87, 152, 137, 25, 107, 214, 19,
          227, 128, 210, 180, 224, 113, 196, 232, 254, 249, 247, 230, 252, 242, 32>>
      }
    account2 = {
        <<4, 176, 20, 135, 174, 148, 149, 10, 132, 176, 41, 79, 141, 161, 151, 96, 65,
          70, 198, 93, 25, 11, 90, 105, 57, 41, 39, 255, 197, 140, 163, 9, 180, 126,
          111, 71, 178, 86, 250, 177, 170, 211, 70, 146, 111, 201, 137, 230, 98, 8,
          205, 109, 234, 51, 50, 140, 9, 177, 130, 222, 196, 54, 98, 55, 243>>,
        <<3, 213, 65, 255, 170, 53, 52, 113, 72, 39, 215, 55, 3, 120, 107, 138, 229, 5,
          32, 56, 255, 130, 166, 97, 131, 94, 156, 186, 57, 55, 189, 228>>
      }
    account3 = {
        <<4, 163, 213, 138, 149, 50, 37, 22, 21, 221, 239, 158, 126, 245, 61, 146, 7,
          15, 86, 26, 224, 169, 46, 191, 199, 39, 172, 189, 146, 10, 111, 160, 51, 7,
          33, 236, 50, 4, 211, 92, 192, 17, 134, 144, 168, 106, 126, 235, 101, 133,
          156, 66, 66, 39, 248, 210, 14, 251, 91, 86, 59, 29, 153, 150, 190>>,
        <<147, 131, 218, 194, 163, 243, 40, 42, 172, 5, 190, 120, 23, 16, 43, 0, 249,
          175, 101, 170, 182, 11, 49, 209, 39, 253, 111, 114, 182, 253, 131, 31>>
      }

    {account1, account2, account3}
  end

  defp get_account_locked_amount() do
    {<<4, 55, 160, 38, 64, 182, 216, 237, 37, 115, 115, 235, 25, 35, 106, 13, 194,
       87, 156, 61, 156, 235, 207, 151, 183, 35, 38, 247, 66, 253, 39, 197, 43, 49,
       55, 78, 125, 31, 45, 38, 203, 156, 1, 206, 235, 241, 50, 140, 195, 38, 19,
       89, 234, 69, 251, 211, 208, 29, 72, 99, 90, 90, 212, 128, 105>>,
     <<132, 73, 10, 38, 77, 68, 7, 72, 211, 181, 33, 176, 209, 113, 210, 159, 247,
       148, 237, 83, 238, 200, 99, 252, 175, 107, 11, 95, 114, 133, 149, 168>>}
  end

  defp create_signed_tx(from_acc, to_acc, value, nonce, fee, lock_time_block \\ 0) do
    {from_acc_pub_key, from_acc_priv_key} = from_acc
    {to_acc_pub_key, _to_acc_priv_key} = to_acc
    {:ok, tx_data} = SpendTx.create(from_acc_pub_key, to_acc_pub_key, value,
                                   nonce, fee, lock_time_block)
    {:ok, signature} = Keys.sign(tx_data, from_acc_priv_key)

    %SignedTx{data: tx_data, signature: signature}
  end

end
