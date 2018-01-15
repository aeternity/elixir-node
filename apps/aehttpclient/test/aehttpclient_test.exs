defmodule AehttpclientTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aehttpclient.Client
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet

  setup wallet do
    [
      pass: "1234"
    ]
  end

  @tag :http_client
  test "Client functions", wallet do
    account = Wallet.get_public_key(wallet.pass)
    hex_acc = Base.encode16(account)

    AehttpclientTest.add_txs_to_pool(wallet.pass)
    assert {:ok, _} = Client.get_info("localhost:4000")
    assert {:ok, _} = Client.get_block({"localhost:4000",
                                        Base.decode16!("414CDFBB4F7090BB11B4ACAD482D2610E651557D54900E61405E51B20FFBAF69")})
    assert {:ok, _} = Client.get_peers("localhost:4000")
    assert Enum.count(Client.get_account_txs({"localhost:4000", hex_acc})
    |> elem(1)) == 2
  end

  def add_txs_to_pool(pass) do
    Miner.mine_sync_block_to_chain
    to_acc = Wallet.get_public_key(pass)

    from_acc = to_acc
    init_nonce = Map.get(Chain.chain_state, from_acc, %{nonce: 0}).nonce
    {:ok, tx1} = TxData.create(from_acc, to_acc, 5, init_nonce + 1, 10)
    {:ok, tx2} = TxData.create(from_acc, to_acc, 5, init_nonce + 2, 10)

    priv_key = Wallet.get_private_key(pass)
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    Pool.add_transaction(signed_tx1)
    Pool.add_transaction(signed_tx2)
  end
end
