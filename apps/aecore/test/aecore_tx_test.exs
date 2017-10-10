defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case
  doctest Aecore.Txs.Tx

  alias Aecore.Txs.Tx, as: Tx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx

  setup do
    Keys.start_link()
    []
  end

  test "create and verify a signed tx" do
    tx = Tx.create("to_account",5)
    assert %SignedTx{} = tx
    assert :true = Tx.verify(tx)
  end

end
