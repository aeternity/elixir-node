defmodule AehttpclientTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Keys.Worker, as: Keys
  alias Aehttpclient.Client

  @tag :http_client
  test "Client functions" do
    account = Keys.pubkey() |> elem(1) |> Base.encode16()
    add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")
    assert {:ok, _} = Client.get_block({"localhost:4000",
      "414CDFBB4F7090BB11B4ACAD482D2610E651557D54900E61405E51B20FFBAF69"})
    assert {:ok, _} = Client.get_peers("localhost:4000")
    assert Enum.count(Client.get_account_txs({"localhost:4000", account})
      |> elem(1)) == 2
  end

  def add_txs_to_pool() do
    {:ok, to_account} = Keys.pubkey()
    init_nonce = Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce
    {:ok, tx1} = Keys.sign_tx(to_account, 5, init_nonce + 1, 1)
    {:ok, tx2} = Keys.sign_tx(to_account, 5, init_nonce + 2, 1)
    Pool.add_transaction(tx1)
    Pool.add_transaction(tx2)
  end
end
