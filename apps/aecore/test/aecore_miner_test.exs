defmodule MinerTest do
  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()
    tests_pow = Application.get_env(:aecore, :pow_module)
    Application.put_env(:aecore, :pow_module, Aecore.Pow.Cuckoo)

    on_exit(fn ->
      TestUtils.clean_blockchain()
      Application.put_env(:aecore, :pow_module, tests_pow)
    end)
  end

  @tag timeout: 20_000
  @tag :miner
  test "mine_next_block" do
    Miner.mine_sync_block_to_chain()
    assert Chain.top_height() >= 1
    assert Chain.top_block().header.height >= 1
    assert length(Chain.longest_blocks_chain()) > 1
    assert Chain.top_block().header.miner == elem(Keys.keypair(:sign), 0)
  end
end
