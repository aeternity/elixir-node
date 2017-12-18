defmodule AehttpclientTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Keys.Worker, as: Keys
  alias Aehttpclient.Client
  alias Aecore.Miner.Worker, as: Miner

  test "Client functions" do
    account = Keys.pubkey() |> elem(1) |> Base.encode16()
    add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")
    assert {:ok, _} = Client.get_block({"localhost:4000",
      Base.decode16!("C061E48A6F7FB2634E0C012B168D41F4773A38BD9E5EA28E5BE7D04186127BA0")})
    assert {:ok, _} = Client.get_peers("localhost:4000")
    assert Enum.count(Client.get_account_txs({"localhost:4000", account})
      |> elem(1)) == 2
  end

  def add_txs_to_pool() do
    Miner.resume()
    Miner.suspend()
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx1} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 10)
    {:ok, tx2} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 10)
    Pool.add_transaction(tx1)
    Pool.add_transaction(tx2)
  end
end
