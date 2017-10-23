defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  setup do
    Pool.start_link()
    []
  end

  test "in multiple blocks" do
    {account1, account2, account3} = get_accounts()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3

    # account A has 100 tokens, spends 100 to B should succeed
    Miner.resume()
    Miner.suspend()
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account2, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    assert 0 == Chain.chain_state[account1_pub_key]
    assert 100 == Chain.chain_state[account2_pub_key]
    Pool.get_and_empty_pool()

    # account1 => 0; account2 => 100

    # account A has 100 tokens, spends 110 to B should be invalid
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account2, 110)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    assert 100 == Chain.chain_state[account1_pub_key]
    Pool.get_and_empty_pool()

    # acccount1 => 100; account2 => 100

    # account A has 100 tokens, spends 40 to B, and two times 30 to C should succeed
    tx = create_signed_tx(account1, account2, 40)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account3, 30)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account3, 30)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    assert 0 == Chain.chain_state[account1_pub_key]
    assert 140 == Chain.chain_state[account2_pub_key]
    assert 60 == Chain.chain_state[account3_pub_key]
    Pool.get_and_empty_pool()

    # account1 => 0; account2 => 140; account3 => 60

    # account A has 100 tokens, spends 50 to B, and two times 30 to C,
    # last transaction to C should be invalid, others be included
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account2, 50)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account3, 30)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account3, 30)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    assert 20 == Chain.chain_state[account1_pub_key]
    assert 190 == Chain.chain_state[account2_pub_key]
    assert 90 == Chain.chain_state[account3_pub_key]
    Pool.get_and_empty_pool()

    # account1 => 20; account2 => 190; account3 => 90

    # account A has 100 tokens, spends 100 to B, B spends 100 to C should succeed
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 80)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account1, account2, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    tx = create_signed_tx(account2, account3, 100)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    assert 0 == Chain.chain_state[account1_pub_key]
    assert 190 == Chain.chain_state[account2_pub_key]
    assert 190 == Chain.chain_state[account3_pub_key]
    Pool.get_and_empty_pool()
  end

  defp get_accounts() do
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

  defp create_signed_tx(from_acc, to_acc, value) do
    {from_acc_pub_key, from_acc_priv_key} = from_acc
    {to_acc_pub_key, _to_acc_priv_key} = to_acc
    {:ok, tx_data} = TxData.create(from_acc_pub_key, to_acc_pub_key, value)
    {:ok, signature} = Keys.sign(tx_data, from_acc_priv_key)

    %SignedTx{data: tx_data, signature: signature}
  end

end
