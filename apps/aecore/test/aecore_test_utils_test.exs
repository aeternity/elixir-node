defmodule AecoreTestUtilsTest do
  @moduledoc """
  Unit test for test_utils testing helper
  """
  use ExUnit.Case
  alias Aecore.Keys
  alias Aecore.Chain.Genesis
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account

  setup do
    Code.require_file("test_utils.ex", "./test")
    :ok
  end

  test "clean_blockchain" do
    TestUtils.clean_blockchain()
    check_is_clean()

    TestUtils.assert_transactions_mined()
    TestUtils.assert_transactions_mined()
    TestUtils.assert_transactions_mined()

    {pubkey, _privkey} = Keys.keypair(:sign)
    assert Account.balance(Chain.chain_state().accounts, pubkey) > 0

    TestUtils.clean_blockchain()
    check_is_clean()
  end

  def check_is_clean do
    {pubkey, _privkey} = Keys.keypair(:sign)
    assert Account.balance(Chain.chain_state().accounts, pubkey) == 0
    assert Chain.top_height() == 0
    assert Chain.top_block() == Genesis.block()
  end
end
