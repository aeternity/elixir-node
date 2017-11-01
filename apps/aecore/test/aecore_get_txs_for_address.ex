defmodule GetTxsForAddressTest do

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.ChainState, as: ChainState
  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.TxData, as: TxData
  alias Aecore.Structures.SignedTx, as: SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.Header, as: Header
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Utils.Blockchain.BlockValidation, as: BlockValidation
  alias Aecore.Txs.Pool.Worker, as: Pool

  setup do
    Chain.start_link()
    []
  end

  @tag timeout: 100000
  test "test2" do

    {:ok, address} = Keys.pubkey()
    address_hex = address |> Base.encode16()
    address_hex_new = String.slice(address_hex, 1,String.length(address_hex))
    address_hex_new = address_hex_new  <> "1"
    address_bin_new = address_hex_new |> Base.decode16!()
    user_pubkey = {:ok, address_bin_new}

    {:ok, tx1} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5, 1)
    {:ok, tx2} = Keys.sign_tx(elem(user_pubkey, 1), 7, 1)
    {:ok, tx3} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5, 1)

    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx2)
    assert :ok = Pool.add_transaction(tx3)
    Miner.resume()
    :timer.sleep(20000)
    Miner.suspend()

    assert 2 <= :erlang.length(Chain.all_blocks)


    assert [tx2] = split_blocks(Chain.all_blocks, address_bin_new, [])
  end


  defp split_blocks([head | tail], address, acc) do
    acc1 = check_address_tx(head.txs, address, acc)
    split_blocks(tail, address, acc1)
  end
  defp split_blocks([], address, acc) do
    acc
  end

  defp check_address_tx([head|tail], address, acc) do
    if head.data.from_acc == address or head.data.to_acc == address  do
      acc = [head.data | acc]
    end

    check_address_tx(tail, address, acc)
  end
   defp check_address_tx([], address, acc) do
    acc
  end
end
