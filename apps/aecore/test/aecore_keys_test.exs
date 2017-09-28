defmodule AecoreKeysTest do
  use ExUnit.Case
  doctest Aecore.Keys.Worker
  alias Aecore.Keys.Worker, as: Keys

  @moduledoc """
  Unit tests for the keys module
  """

  setup do
    Keys.start_link()
    []
  end

  test "test if a pubkey is loaded" do
    assert {:ok,_key} = Keys.pubkey()
  end

  test "sign fake coinbase transaction and verify the signed transaction" do
    {:ok, from_acc} = Keys.pubkey()
    coinbase_tx = %{:from_acc => from_acc,
                    :to_acc   => "to account",
                    :value    => 5}
    assert {:ok, %{data: data,signature: signature}} = Keys.sign(coinbase_tx)
    assert :true = Keys.verify(data,signature,data.from_acc)
  end
end
