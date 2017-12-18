defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx

  setup do
    Keys.start_link([])
    []
  end

  test "create and verify a signed tx" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, 5,
                             Map.get(Chain.chain_state,
                                     to_account, %{nonce: 0}).nonce + 1, 1,
                             Chain.top_block().header.height +
                              Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1)

    assert :true = Keys.verify_tx(tx)
  end

  test "positive tx valid" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, 5, Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    assert SignedTx.is_valid(tx)
  end

  test "negative tx invalid" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, -5, Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    assert !SignedTx.is_valid(tx)
  end

end
