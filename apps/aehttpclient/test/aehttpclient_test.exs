defmodule AehttpclientTest do

  use ExUnit.Case

  alias Aecore.Structures.Block
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Keys.Worker, as: Keys
  alias Aehttpclient.Client

  test "Client functions" do
    add_txs_to_pool()
    Peers.add_peer("localhost:4000")
    genesis_block = Block.genesis_block()
    assert {:ok, _} = Client.get_info("localhost:4000")
    assert {:ok, genesis_block} = Client.get_block({"localhost:4000",
      "C061E48A6F7FB2634E0C012B168D41F4773A38BD9E5EA28E5BE7D04186127BA0"})
    assert {:ok, _} = Client.get_peers("localhost:4000")
    assert Enum.count(Client.get_account_txs({"localhost:4000",
    "043DD9E21016F591C2D8BB616C76DA96474A9A82E9E02CE6AC264E84F6E8BA2A971271EEC4185005499ECB729601535D852798262F331ADCDA65A607AAE0CFE384"
      }) |> elem(1)) == 2
  end

  def add_txs_to_pool() do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx1} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1)
    {:ok, tx2} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1)
    Pool.add_transaction(tx1)
    Pool.add_transaction(tx2)
  end
end
