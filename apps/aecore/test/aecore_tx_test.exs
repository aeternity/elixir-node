defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx

  setup do
    Keys.start_link([])
    []
  end

  @tag :tx
  test "create and verify a SpendTx and DataTx" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx1} = Keys.sign_tx(to_account, 5,
                             Map.get(Chain.chain_state,
                                     to_account, %{nonce: 0}).nonce + 1, 1,
                             Chain.top_block().header.height +
                              Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1)

    assert :true = Keys.verify_tx(tx1)

    tx2 = DataTx.create(:poe, %{some: "data"}, 5, 2)
    assert :true = Keys.verify_tx(tx2)
  end

  test "positive tx valid" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, 5, Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    assert SignedTx.is_valid?(tx)
  end

  test "negative tx invalid" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, -5, Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    assert !SignedTx.is_valid?(tx)
  end

end
