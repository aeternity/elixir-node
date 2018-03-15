defmodule AehttpclientTest do
  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aehttpclient.Client
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Bits
  alias Aewallet.Encoding

  @tag :http_client
  test "Client functions" do
    account = Wallet.get_public_key()
    hex_acc = Encoding.encode(account, :ae)
    bech32_encoded_top_block_hash = Bits.bech32_encode("bl", Chain.top_block_hash)

    AehttpclientTest.add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")

    assert {:ok, _} =
             Client.get_block(
               {"localhost:4000",
                Bits.bech32_decode(
                  bech32_encoded_top_block_hash
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

    init_nonce = Map.get(Chain.chain_state, from_acc, %{nonce: 0}).nonce
    payload1 = %{to_acc: from_acc,
                 value: 5,
                 lock_time_block: 0}

    tx1 = DataTx.init(SpendTx, payload1, to_acc, 10, init_nonce + 1)
    tx2 = DataTx.init(SpendTx, payload1, to_acc, 10, init_nonce + 2)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
  end
end
