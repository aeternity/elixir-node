defmodule AecoreKeysTest do
  @moduledoc """
  Unit tests for the keys module
  """

  use ExUnit.Case
  doctest Aecore.Keys.Worker

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData, as: TxData
  alias Aecore.Structures.SignedTx, as: SignedTx

  setup do
    Keys.start_link()
    []
  end

  test "test if a pubkey is loaded" do
    assert {:ok,_key} = Keys.pubkey()
  end

  test "sign transaction" do
    {:ok, from_acc} = Keys.pubkey()
    tx = %TxData{from_acc: from_acc, to_acc: "to account",value: 5}
    assert {:ok, _} = Keys.sign(tx)
  end
end
