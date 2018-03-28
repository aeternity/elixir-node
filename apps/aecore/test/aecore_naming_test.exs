defmodule AecoreNamingTest do
  @moduledoc """
  Unit tests for the Aecore.Naming module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.Account

  setup do
    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)
  end

  test "test naming workflow", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert 1 == Enum.count(first_name.pre_claims)

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert Enum.empty?(first_name.pre_claims)
    assert 1 == Enum.count(first_name.claims)
    [first_claim] = first_name.claims
    assert "test.aet" == first_claim.name
    assert "" == first_claim.pointers

    {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 5)
    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert Enum.empty?(first_name.pre_claims)
    assert 1 == Enum.count(first_name.claims)
    [first_claim] = first_name.claims
    assert "test.aet" == first_claim.name
    assert "{\"test\": 2}" == first_claim.pointers
  end
end
