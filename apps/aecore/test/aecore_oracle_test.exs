defmodule AecoreOracleTest do
  use ExUnit.Case

  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Persistence.Worker, as: Persistence

  setup do
    Code.require_file("test_utils.ex", "./test")

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      Pool.get_and_empty_pool()
      :ok
    end)
  end

  @tag timeout: 120_000
  @tag :oracle_test
  test "register and query an oracle, check response, check if invalid transactions are filtered out" do
    Pool.get_and_empty_pool()
    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Chain.registered_oracles()) == true
    register_oracle(:valid)

    Miner.mine_sync_block_to_chain()

    assert Enum.empty?(Chain.registered_oracles()) == false
    Miner.mine_sync_block_to_chain()
    pub_key = Wallet.get_public_key()

    assert %{} == Pool.get_and_empty_pool()

    assert true == Chain.registered_oracles() |> Map.keys() |> Enum.member?(pub_key)

    query_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    assert %{} == Pool.get_and_empty_pool()

    oracle_respond(:valid)
    Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    interaction_object = Chain.oracle_interaction_objects() |> Map.values() |> Enum.at(0)
    assert nil != interaction_object.response
    Chain.clear_state()

    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    register_oracle(:invalid, :format)
    register_oracle(:invalid, :ttl)
    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Chain.registered_oracles()) == true
    Chain.clear_state()
    register_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Chain.registered_oracles()) == false
    query_oracle(:invalid, :address)
    query_oracle(:invalid, :query_data)
    query_oracle(:invalid, :query_fee)
    query_oracle(:invalid, :ttl)
    Miner.mine_sync_block_to_chain()

    assert Enum.empty?(Chain.oracle_interaction_objects()) == true

    query_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    oracle_respond(:invalid, :id)
    oracle_respond(:invalid, :response_data)
    Miner.mine_sync_block_to_chain()

    assert Chain.oracle_interaction_objects()
           |> Map.values()
           |> Enum.map(fn object -> object.response end)
           |> Enum.all?(fn response -> response == :undefined end)

    oracle_respond(:valid)
    Miner.mine_sync_block_to_chain()

    assert Chain.oracle_interaction_objects()
           |> Map.values()
           |> Enum.map(fn object -> object.response end)
           |> Enum.all?(fn response -> response != :undefined end)

    Chain.clear_state()
    register_oracle(:valid)
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    Oracle.extend(3, 10)
    Miner.mine_sync_block_to_chain()
    oracle = Chain.registered_oracles() |> Map.values() |> Enum.at(0)
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
        oracle_address = Chain.registered_oracles() |> Map.keys() |> Enum.at(0)
        Oracle.query(oracle_address, %{"currency" => "USD"}, 5, 10, ttl, ttl)

      :invalid ->
        case field do
          :address ->
            ttl = get_ttl(:valid)
            oracle_address = <<1, 2, 3>>
            Oracle.query(oracle_address, %{"currency" => "USD"}, 5, 10, ttl, ttl)

          :query_data ->
            ttl = get_ttl(:valid)
            oracle_address = Chain.registered_oracles() |> Map.keys() |> Enum.at(0)
            Oracle.query(oracle_address, %{"currency" => 5}, 5, 10, ttl, ttl)

          :query_fee ->
            ttl = get_ttl(:valid)
            oracle_address = Chain.registered_oracles() |> Map.keys() |> Enum.at(0)
            Oracle.query(oracle_address, %{"currency" => "USD"}, 3, 10, ttl, ttl)

          :ttl ->
            ttl = get_ttl(validity)
            oracle_address = Chain.registered_oracles() |> Map.keys() |> Enum.at(0)
            Oracle.query(oracle_address, %{"currency" => "USD"}, 5, 10, ttl, ttl)
        end
    end
  end

  def oracle_respond(validity, field \\ nil) do
    case validity do
      :valid ->
        query_id = Chain.oracle_interaction_objects() |> Map.keys() |> Enum.at(0)
        Oracle.respond(query_id, %{"currency" => "BGN"}, 5)

      :invalid ->
        case field do
          :id ->
            query_id = <<1, 2, 3>>
            Oracle.respond(query_id, %{"currency" => "BGN"}, 5)

          :response_data ->
            query_id = Chain.oracle_interaction_objects() |> Map.keys() |> Enum.at(0)
            Oracle.respond(query_id, %{"currency" => 5}, 5)
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
        %{
          "type" => "object",
          "properties" => %{"currency" => %{"type" => "string"}}
        }

      :invalid ->
        %{
          "type" => "something",
          "properties" => %{"currency" => %{"type" => "else"}}
        }
    end
  end
end
