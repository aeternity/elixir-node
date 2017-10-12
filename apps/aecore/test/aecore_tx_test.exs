defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx

  setup do
    Keys.start_link()
    []
  end

  test "create and verify a signed tx" do
    {:ok, to_account} = Keys.pubkey()
    tx = SignedTx.create(to_account, 5)

    assert %SignedTx{} = tx
    assert :true = SignedTx.verify(tx)
  end

end
