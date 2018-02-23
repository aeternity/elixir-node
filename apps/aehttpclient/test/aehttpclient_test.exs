defmodule AehttpclientTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Keys.Worker, as: Keys
  alias Aehttpclient.Client
  alias Aecore.Miner.Worker, as: Miner
  alias Aeutil.Bits

  @tag :http_client
  test "Client functions" do
    account = Keys.pubkey() |> elem(1) |> Base.encode16()
    add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")
    assert {:ok, _} = Client.get_block({"localhost:4000",
                                        Bits.bech32_decode("bl1qpqwc2g9w0c06u2yxmgrffr50r508z9zww3jhca9x6xx57kfg2pcsrhq9dp")})
    assert {:ok, _} = Client.get_peers("localhost:4000")
    assert Enum.count(Client.get_account_txs({"localhost:4000", account})
    |> elem(1)) == 2
  end

  def add_txs_to_pool() do
    Miner.mine_sync_block_to_chain
    {:ok, to_account} = Keys.pubkey()

    init_nonce = Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce
    {:ok, tx1} = Keys.sign_tx(to_account, 5, init_nonce + 1, 10)
    {:ok, tx2} = Keys.sign_tx(to_account, 5, init_nonce + 2, 10)

    Pool.add_transaction(tx1)
    Pool.add_transaction(tx2)
  end
end
