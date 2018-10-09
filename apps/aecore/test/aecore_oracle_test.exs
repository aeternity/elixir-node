defmodule AecoreOracleTest do
  use ExUnit.Case

  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys
  alias Aeutil.PatriciaMerkleTree

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  @tag timeout: 120_000
  @tag :oracle_test
  test "register and query an oracle, check response, check if invalid transactions are filtered out" do
    Pool.get_and_empty_pool()
    Miner.mine_sync_block_to_chain()
    oracle_tree_1 = Chain.chain_state().oracles.oracle_tree

    assert oracle_tree_1 |> PatriciaMerkleTree.all_keys() |> Enum.empty?() == true
    register_oracle(:valid)

    Miner.mine_sync_block_to_chain()
    oracle_tree_2 = Chain.chain_state().oracles.oracle_tree
    assert oracle_tree_2 |> PatriciaMerkleTree.all_keys() |> Enum.empty?() == false

    Miner.mine_sync_block_to_chain()
    pub_key = elem(Keys.keypair(:sign), 0)

    assert %{} == Pool.get_and_empty_pool()

    oracle_tree_3 = Chain.chain_state().oracles.oracle_tree
    assert oracle_tree_3 |> PatriciaMerkleTree.all_keys() |> Enum.member?(pub_key) == true

    query_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    assert %{} == Pool.get_and_empty_pool()

    oracle_respond(:valid)
    Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    oracle_tree_4 = Chain.chain_state().oracles.oracle_tree
    query_id = oracle_tree_4 |> PatriciaMerkleTree.all_keys() |> List.last()
    interaction_object = OracleStateTree.get_query(Chain.chain_state().oracles, query_id)
    assert nil != interaction_object.response
    Chain.clear_state()

    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    register_oracle(:invalid, :format)
    register_oracle(:invalid, :ttl)
    Miner.mine_sync_block_to_chain()

    oracle_tree_5 = Chain.chain_state().oracles.oracle_tree
    assert oracle_tree_5 |> PatriciaMerkleTree.all_keys() |> Enum.empty?() == true

    Chain.clear_state()
    register_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()

    oracle_tree_6 = Chain.chain_state().oracles.oracle_tree
    assert oracle_tree_6 |> PatriciaMerkleTree.all_keys() |> Enum.empty?() == false

    query_oracle(:invalid, :address)
    query_oracle(:invalid, :query_data)
    query_oracle(:invalid, :query_fee)
    query_oracle(:invalid, :ttl)
    Miner.mine_sync_block_to_chain()

    assert Chain.top_block().txs == []

    query_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    oracle_respond(:invalid, :id)
    oracle_respond(:invalid, :response_data)
    Miner.mine_sync_block_to_chain()

    oracle_tree_7 = Chain.chain_state().oracles.oracle_tree
    query_key_1 = oracle_tree_7 |> PatriciaMerkleTree.all_keys() |> List.last()
    query_1 = OracleStateTree.get_query(Chain.chain_state().oracles, query_key_1)
    assert query_1.response == :undefined

    oracle_respond(:valid)
    Miner.mine_sync_block_to_chain()

    oracle_tree_8 = Chain.chain_state().oracles.oracle_tree
    query_key_2 = oracle_tree_8 |> PatriciaMerkleTree.all_keys() |> List.last()
    query_2 = OracleStateTree.get_query(Chain.chain_state().oracles, query_key_2)
    assert query_2.response != :undefined

    Chain.clear_state()
    register_oracle(:valid)

    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()

    Oracle.extend(%{ttl: 3, type: :relative}, 10)
    Miner.mine_sync_block_to_chain()

    oracle_tree_9 = Chain.chain_state().oracles.oracle_tree
    oracle_key = oracle_tree_9 |> PatriciaMerkleTree.all_keys() |> List.first()
    oracle = OracleStateTree.get_oracle(Chain.chain_state().oracles, oracle_key)
    assert oracle.expires == 15

    Chain.clear_state()
  end

  def register_oracle(validity, field \\ nil) do
    case validity do
      :valid ->
        format = get_format(validity)

        Oracle.register(
          format,
          format,
          5,
          5,
          get_ttl(validity)
        )

      :invalid ->
        case field do
          :format ->
            format = get_format(validity)

            Oracle.register(
              format,
              format,
              5,
              5,
              get_ttl(:valid)
            )

          :ttl ->
            format = get_format(:valid)
            Oracle.register(format, format, 5, 5, get_ttl(validity))
        end
    end
  end

  def query_oracle(validity, field \\ nil) do
    case validity do
      :valid ->
        ttl = get_ttl(validity)
        oracle_tree = Chain.chain_state().oracles.oracle_tree
        oracle_address = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.first()
        Oracle.query(oracle_address, "foo: bar", 5, 10, ttl, ttl)

      :invalid ->
        case field do
          :address ->
            ttl = get_ttl(:valid)
            oracle_address = <<1, 2, 3>>
            Oracle.query(oracle_address, "foo: bar", 5, 10, ttl, ttl)

          :query_data ->
            ttl = get_ttl(:valid)
            oracle_tree = Chain.chain_state().oracles.oracle_tree
            oracle_address = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.first()
            Oracle.query(oracle_address, 6, 5, 10, ttl, ttl)

          :query_fee ->
            ttl = get_ttl(:valid)
            oracle_tree = Chain.chain_state().oracles.oracle_tree
            oracle_address = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.first()
            Oracle.query(oracle_address, "foo: bar", 3, 10, ttl, ttl)

          :ttl ->
            ttl = get_ttl(validity)
            oracle_tree = Chain.chain_state().oracles.oracle_tree
            oracle_address = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.first()
            Oracle.query(oracle_address, "foo: bar", 5, 10, ttl, ttl)
        end
    end
  end

  def oracle_respond(validity, field \\ nil) do
    case validity do
      :valid ->
        oracle_tree = Chain.chain_state().oracles.oracle_tree
        tree_query_id = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.last()
        <<_::binary-size(32), query_id::binary>> = tree_query_id
        Oracle.respond(query_id, "boolean", 5)

      :invalid ->
        case field do
          :id ->
            query_id = <<1, 2, 3>>
            Oracle.respond(query_id, "boolean", 5)

          :response_data ->
            oracle_tree = Chain.chain_state().oracles.oracle_tree
            tree_query_id = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.last()
            <<_::binary-size(32), query_id::binary>> = tree_query_id
            Oracle.respond(query_id, 70, 5)
        end
    end
  end

  def get_ttl(validity) do
    case validity do
      :valid ->
        %{ttl: 10, type: :relative}

      :invalid ->
        %{ttl: 1, type: :absolute}
    end
  end

  def get_format(validity) do
    case validity do
      :valid ->
        "foo: bar"

      :invalid ->
        30
    end
  end
end
