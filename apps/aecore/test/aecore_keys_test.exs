defmodule AecoreKeysTest do
  @moduledoc """
  Unit tests for the keys module
  """

  use ExUnit.Case
  doctest Aecore.Keys.Worker

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Keys.start_link()
    []
  end

  test "test if a pubkey is loaded" do
    assert {:ok, _key} = Keys.pubkey()
  end

  test "sign transaction" do
    {:ok, to_account} = Keys.pubkey()
    assert {:ok, _} = Keys.sign_tx(to_account, 5, Map.get(Chain.chain_state(), to_account, %{nonce: 0}).nonce + 1)
  end
end
