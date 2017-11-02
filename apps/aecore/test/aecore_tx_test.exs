defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Keys.start_link([])
    []
  end

  test "create and verify a signed tx" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, 5, Map.get(Chain.chain_state(), to_account, %{nonce: 0}).nonce + 1)

    assert :true = Keys.verify_tx(tx)
  end

end
