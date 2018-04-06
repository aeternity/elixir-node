defmodule AehttpclientTest do
  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aehttpclient.Client
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Header
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet

  @tag :http_client
  test "Client functions" do
    account = Wallet.get_public_key()
    hex_acc = Account.base58c_encode(account)
    base58_encoded_top_block_hash = Header.base58c_encode(Chain.top_block_hash())
    Pool.get_and_empty_pool()
    add_txs_to_pool()
    assert {:ok, _} = Client.get_info("localhost:4000")

    assert {:ok, _} =
             Client.get_block(
               {"localhost:4000", Header.base58c_decode(base58_encoded_top_block_hash)}
             )

    assert {:ok, _} = Client.get_peers("localhost:4000")

    assert Enum.count(
             Client.get_account_txs({"localhost:4000", hex_acc})
             |> elem(1)
           ) == 2
  end

  def add_txs_to_pool() do
    Miner.mine_sync_block_to_chain()
    receiver = Wallet.get_public_key()
    sender = receiver

    init_nonce = Map.get(Chain.chain_state(), sender, %{nonce: 0}).nonce
    payload1 = %{receiver: sender, amount: 5}

    tx1 = DataTx.init(SpendTx, payload1, receiver, 10, init_nonce + 1)
    tx2 = DataTx.init(SpendTx, payload1, receiver, 10, init_nonce + 2)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
  end
end
