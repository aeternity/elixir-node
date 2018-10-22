defmodule AehttpclientTest do
  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aehttpclient.Client
  alias Aecore.Chain.Header
  alias Aecore.Account.Account
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys

  @tag :http_client
  test "Client functions" do
    {account, _} = Keys.keypair(:sign)
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

    acc_txs =
      {"localhost:4000", hex_acc}
      |> Client.get_account_txs()
      |> elem(1)

    assert Enum.count(acc_txs) == 2
  end

  def add_txs_to_pool do
    Miner.mine_sync_block_to_chain()
    {sender, priv_key} = Keys.keypair(:sign)
    receiver = sender

    init_nonce = Map.get(Chain.chain_state(), sender, %{nonce: 0}).nonce

    signed_tx1 = Account.spend(sender, priv_key, receiver, 5, 10, init_nonce + 1, <<"payload">>)

    signed_tx2 = Account.spend(sender, priv_key, receiver, 5, 10, init_nonce + 2, <<"payload">>)

    txs_in_the_pool = Pool.get_pool() |> Map.values() |> Enum.sort()

    assert Enum.sort([signed_tx1, signed_tx2]) == txs_in_the_pool
  end
end
