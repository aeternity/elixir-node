defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Tx module
  """

  use ExUnit.Case
  doctest Aecore.Tx

  alias Aecore.Tx, as: Tx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx

  setup do
    Keys.start_link()
    []
  end

  test "create a signed tx" do
    tx = Tx.create("to_account",5)
    assert %SignedTx{} = tx
  end

end
