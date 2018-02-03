defmodule AecoreVotingOnChainTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.VotingOnChain, as: Voting
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  @tag timeout: 20_000
  test "try making some invalid question txs" do
    {:ok, pk} = Keys.pubkey()
    Miner.mine_sync_block_to_chain #make sure we have tokens
    assert Chain.chain_state[pk].balance >= 100

    {:ok, tx1} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height, Chain.top_height + 10, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b"]), true))
    {:ok, tx2} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height + 10, Chain.top_height + 10, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b"]), true))
    {:ok, tx3} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height + 5, Chain.top_height + 10, "ASDFASDF", Voting.get_single_choice_initial_state(["a", "b"]),true))
       
    chainstate_calculation_header =
        Header.create(
          Chain.top_block.header.height + 1,
          Chain.top_block_hash,
          <<0>>,
          <<0>>,
          1,
          0,
          Block.current_block_version()
        )
    assert {{false, _}, _} = BlockValidation.validate_transaction_chainstate(tx1, Chain.chain_state, chainstate_calculation_header)
    assert {{false, _}, _} = BlockValidation.validate_transaction_chainstate(tx2, Chain.chain_state, chainstate_calculation_header)
    assert {{false, _}, _} = BlockValidation.validate_transaction_chainstate(tx3, Chain.chain_state, chainstate_calculation_header)

    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx2)
    assert :ok = Pool.add_transaction(tx3)

    Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool

    assert Enum.count(Chain.top_block().txs) == 1 #only coinbase tx

    Miner.mine_sync_block_to_chain
  end

  test "votes tests" do
   
    {:ok, pk} = Keys.pubkey()
    Miner.mine_sync_block_to_chain #make sure we have tokens
    Miner.mine_sync_block_to_chain #make sure we have tokens
    begin_height = Chain.top_height + 2
    {a1, a2, a3} = get_accounts()

    {:ok, q_tx} = Keys.sign_txdata(Voting.create_question_tx("The voting", Chain.top_height + 2, Chain.top_height + 3, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b", "c"]), true))
   
    chainstate_calculation_header =
        Header.create(
          Chain.top_block.header.height + 1,
          Chain.top_block_hash,
          <<0>>,
          <<0>>,
          1,
          0,
          Block.current_block_version()
        )
    voting_hash = Voting.get_hash(Voting.create_from_tx!(q_tx.data, chainstate_calculation_header))
    {:ok, s1_tx} = Keys.sign_tx(a1.pk, 30, Chain.chain_state[pk].nonce + 2, 10)
    {:ok, s2_tx} = Keys.sign_tx(a2.pk, 30, Chain.chain_state[pk].nonce + 3, 10)
    Pool.add_transaction(q_tx)
    Pool.add_transaction(s1_tx)
    Pool.add_transaction(s2_tx)
    Miner.mine_sync_block_to_chain
    assert Chain.top_height == begin_height - 1
    assert Pool.get_pool == %{}
    assert Enum.count(Chain.top_block.txs) == 4 #coinbase plus above
    assert Map.has_key?(Chain.chain_state, voting_hash)


    {:ok, v1} = Keys.sign_txdata(elem(TxData.create(pk, voting_hash, 0, Chain.chain_state[pk].nonce + 1, 10, 0, %{choice: "a"}), 1)) #too fast vote
    Pool.add_transaction(v1)
    Miner.mine_sync_block_to_chain
    
    assert Chain.top_height == begin_height #voting will be allowed in next block
    assert Pool.get_and_empty_pool != %{}

    voting_state = Chain.chain_state[voting_hash]
    assert voting_state.state == Voting.get_single_choice_initial_state(["a", "b", "c"])
    assert voting_state.initial_state == Voting.get_single_choice_initial_state(["a", "b", "c"])
    assert voting_state.requester == pk
    assert voting_state.comment == "The voting"
    assert voting_state.formula == Voting.code_single_choice
    assert voting_state.start_height == begin_height
    assert voting_state.end_height == begin_height + 1
    {:ok, v2} = Keys.sign_txdata(elem(TxData.create(pk, voting_hash, 0, Chain.chain_state[pk].nonce + 1, 10, 0, %{choice: "b"}), 1)) #good vote
    {:ok, s3_tx} = Keys.sign_tx(a2.pk, 10, Chain.chain_state[pk].nonce + 2, 10)
    miner_tokens_at_start = Chain.chain_state[pk].balance
    {:ok, v3} = Keys.sign_txdata(elem(TxData.create(a2.pk, voting_hash, 0, 1, 10, 0, %{choice: "b"}), 1), a2.sk) #good vote
    {:ok, v4} = Keys.sign_txdata(elem(TxData.create(a2.pk, voting_hash, 0, 2, 10, 0, %{choice: "c"}), 1), a2.sk) #double vote
    {:ok, v5} = Keys.sign_txdata(elem(TxData.create(a1.pk, voting_hash, 0, 1, 10, 0, %{choice: "d"}), 1), a1.sk) #wrong choice
    Pool.add_transaction(v2)
    Pool.add_transaction(s3_tx)
    Pool.add_transaction(v3)
    Pool.add_transaction(v4)
    Pool.add_transaction(v5)
    Miner.mine_sync_block_to_chain
    
    assert Chain.top_height == begin_height + 1 #voting has just closed
    assert Pool.get_and_empty_pool == tx_list_to_map([v4, v5])
    assert Enum.count(Chain.top_block.txs) == 4 #2 votes, 1 spend, 1 coinbase
    assert Chain.chain_state[voting_hash].state == %{voters: %{pk => true, a2.pk => true}, results: %{"a" => 0, "b" => miner_tokens_at_start + 30, "c" => 0}}
    {:ok, v6} = Keys.sign_txdata(elem(TxData.create(a1.pk, voting_hash, 0, 2, 10, 0, %{choice: "c"}), 1), a1.sk) #too late
    Pool.add_transaction(v6)
    Miner.mine_sync_block_to_chain
    assert Pool.get_and_empty_pool == tx_list_to_map([v6])
    assert Enum.count(Chain.top_block.txs) == 1 #1 coinbase
    assert Chain.chain_state[voting_hash].state == %{voters: %{pk => true, a2.pk => true}, results: %{"a" => 0, "b" => miner_tokens_at_start + 30, "c" => 0}}
  end

  defp tx_list_to_map(txs) do
    Enum.reduce(txs,
                %{},
                fn (tx, acc) ->
                  Map.put(acc, SignedTx.hash(tx), tx)
                end)
  end

  defp get_accounts() do
    account1 = %{
      pk: <<4, 94, 96, 161, 182, 76, 153, 22, 179, 136, 60, 87, 225, 135, 253, 179, 80,
          40, 80, 149, 21, 26, 253, 48, 139, 155, 200, 45, 150, 183, 61, 46, 151, 42,
          245, 199, 168, 60, 121, 39, 180, 82, 162, 173, 86, 194, 180, 54, 116, 190,
          199, 155, 97, 222, 85, 83, 147, 172, 10, 85, 112, 29, 54, 0, 78>>,
      sk: <<214, 90, 19, 166, 30, 35, 31, 96, 16, 116, 48, 33, 26, 76, 192, 195, 104,
          242, 147, 120, 240, 124, 112, 222, 213, 112, 142, 218, 49, 33, 6, 81>>
      }
    account2 = %{
      pk: <<4, 205, 231, 80, 153, 60, 210, 201, 30, 39, 4, 191, 92, 231, 80, 143, 98,
          143, 46, 150, 175, 162, 230, 59, 56, 2, 60, 238, 206, 218, 239, 177, 201, 66,
          161, 205, 159, 69, 177, 155, 172, 222, 43, 225, 241, 181, 226, 244, 106, 23,
      114, 161, 65, 121, 146, 35, 27, 136, 15, 142, 228, 22, 217, 78, 90>>,
      sk:
        <<151, 121, 56, 150, 179, 169, 141, 25, 212, 247, 156, 162, 120, 205, 59, 184,
          49, 201, 75, 67, 170, 113, 157, 114, 129, 149, 206, 62, 182, 239, 146, 26>>
      }
    account3 = %{
      pk: <<4, 167, 170, 180, 131, 214, 204, 39, 21, 99, 168, 142, 78, 66, 54, 118, 143,
          18, 28, 73, 62, 255, 220, 172, 4, 166, 255, 54, 72, 39, 34, 233, 23, 124,
          242, 120, 68, 145, 79, 31, 63, 168, 166, 87, 153, 108, 93, 92, 249, 6, 21,
          75, 159, 180, 17, 18, 6, 186, 42, 199, 140, 254, 115, 165, 199>>,
      sk: <<158, 99, 132, 39, 80, 18, 118, 135, 107, 173, 203, 149, 238, 177, 124, 169,
          207, 241, 200, 73, 154, 108, 205, 151, 103, 197, 21, 0, 183, 163, 137, 228>>
      }

      {account1, account2, account3}
  end

end
