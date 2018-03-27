defmodule AehttpclientTest do
  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aehttpclient.Client
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Account
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Bits
  alias Aewallet.Encoding

  @tag :http_client
  test "Client functions" do
    account = Wallet.get_public_key()
    hex_acc = Encoding.encode(account, :ae)

    AehttpclientTest.add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")

    assert {:ok, _} =
             Client.get_block(
               {"localhost:4000",
                Bits.bech32_decode(
                  "bl1qpqwc2g9w0c06u2yxmgrffr50r508z9zww3jhca9x6xx57kfg2pcsrhq9dp"
                )}
             )

    assert {:ok, _} = Client.get_peers("localhost:4000")

    assert Enum.count(
             Client.get_account_txs({"localhost:4000", hex_acc})
             |> elem(1)
           ) == 2
  end

  def add_txs_to_pool() do
    Miner.mine_sync_block_to_chain()
    to_acc = Wallet.get_public_key()
    from_acc = to_acc

    init_nonce = Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce

    # the order of to_acc and from_acc is reversed intentionally. priv_key is key for to_acc
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = Account.spend(to_acc, priv_key, from_acc, 5, 10, init_nonce + 1)
    {:ok, signed_tx2} = Account.spend(to_acc, priv_key, from_acc, 5, 10, init_nonce + 2)

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
  end
end
