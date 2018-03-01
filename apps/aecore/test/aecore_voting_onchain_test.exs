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

  @a1 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))
  @a2 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))
  @a3 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))
  @a4 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))

  test "try making some invalid question txs" do
    {:ok, pk} = Keys.pubkey()
    Miner.mine_sync_block_to_chain #make sure we have tokens
    assert Chain.chain_state[pk].balance >= 100

    {:ok, tx1} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height, Chain.top_height + 10, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b"]), 50, true))
    {:ok, tx2} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height + 10, Chain.top_height + 10, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b"]), 50, true))
    {:ok, tx3} = Keys.sign_txdata(Voting.create_question_tx("", Chain.top_height + 5, Chain.top_height + 10, "ASDFASDF", Voting.get_single_choice_initial_state(["a", "b"]), 50, true))
       
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
    {a1pk, a1sk} = @a1
    {a2pk, a2sk} = @a2

    {:ok, q_tx} = Keys.sign_txdata(Voting.create_question_tx("The voting", Chain.top_height + 2, Chain.top_height + 3, Voting.code_single_choice, Voting.get_single_choice_initial_state(["a", "b", "c"])))
   
    voting_hash = Voting.get_hash(q_tx.data)
    {:ok, s1_tx} = Keys.sign_tx(a1pk, 30, Chain.chain_state[pk].nonce + 2, 10)
    {:ok, s2_tx} = Keys.sign_tx(a2pk, 30, Chain.chain_state[pk].nonce + 3, 10)
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
    {:ok, s3_tx} = Keys.sign_tx(a2pk, 10, Chain.chain_state[pk].nonce + 2, 10)
    miner_tokens_at_start = Chain.chain_state[pk].balance
    {:ok, v3} = Keys.sign_txdata(elem(TxData.create(a2pk, voting_hash, 0, 1, 10, 0, %{choice: "b"}), 1), a2sk) #good vote
    {:ok, v4} = Keys.sign_txdata(elem(TxData.create(a2pk, voting_hash, 0, 2, 10, 0, %{choice: "c"}), 1), a2sk) #double vote
    {:ok, v5} = Keys.sign_txdata(elem(TxData.create(a1pk, voting_hash, 0, 1, 10, 0, %{choice: "d"}), 1), a1sk) #wrong choice
    Pool.add_transaction(v2)
    Pool.add_transaction(s3_tx)
    Pool.add_transaction(v3)
    Pool.add_transaction(v4)
    Pool.add_transaction(v5)
    Miner.mine_sync_block_to_chain
    
    assert Chain.top_height == begin_height + 1 #voting has just closed
    assert Pool.get_and_empty_pool == tx_list_to_map([v4, v5])
    assert Enum.count(Chain.top_block.txs) == 4 #2 votes, 1 spend, 1 coinbase
    assert Chain.chain_state[voting_hash].state == %{voters: %{pk => true, a2pk => true}, results: %{"a" => 0, "b" => miner_tokens_at_start + 30, "c" => 0}}
    {:ok, v6} = Keys.sign_txdata(elem(TxData.create(a1pk, voting_hash, 0, 2, 10, 0, %{choice: "c"}), 1), a1sk) #too late
    Pool.add_transaction(v6)
    Miner.mine_sync_block_to_chain
    assert Pool.get_and_empty_pool == tx_list_to_map([v6])
    assert Enum.count(Chain.top_block.txs) == 1 #1 coinbase
    assert Chain.chain_state[voting_hash].state == %{voters: %{pk => true, a2pk => true}, results: %{"a" => 0, "b" => miner_tokens_at_start + 30, "c" => 0}}
  end
  
  test "mutli choice tests" do
   
    {:ok, pk} = Keys.pubkey()
    Miner.mine_sync_block_to_chain #make sure we have tokens
    Miner.mine_sync_block_to_chain #make sure we have tokens
    begin_height = Chain.top_height + 1
    {a1pk, a1sk} = @a3
    {a2pk, a2sk} = @a4

    {:ok, q_tx} = Keys.sign_txdata(Voting.create_question_tx("The voting 2", Chain.top_height + 1, Chain.top_height + 2, Voting.code_multi_choice, Voting.get_multi_choice_initial_state(["a", "b", "c"])))
   
    voting_hash = Voting.get_hash(q_tx.data)
    {:ok, s1_tx} = Keys.sign_tx(a1pk, 30, Chain.chain_state[pk].nonce + 2, 10)
    {:ok, s2_tx} = Keys.sign_tx(a2pk, 30, Chain.chain_state[pk].nonce + 3, 10)
    Pool.add_transaction(q_tx)
    Pool.add_transaction(s1_tx)
    Pool.add_transaction(s2_tx)
    Miner.mine_sync_block_to_chain
    assert Pool.get_pool == %{}
    assert Enum.count(Chain.top_block.txs) == 4 #coinbase plus above
    assert Map.has_key?(Chain.chain_state, voting_hash)
    assert Chain.top_height == begin_height #voting will be allowed in next block

    voting_state = Chain.chain_state[voting_hash]
    assert voting_state.state == Voting.get_multi_choice_initial_state(["a", "b", "c"])
    assert voting_state.initial_state == Voting.get_multi_choice_initial_state(["a", "b", "c"])
    assert voting_state.requester == pk
    assert voting_state.comment == "The voting 2"
    assert voting_state.formula == Voting.code_multi_choice
    assert voting_state.start_height == begin_height
    assert voting_state.end_height == begin_height + 1
    {:ok, v2} = Keys.sign_txdata(elem(TxData.create(pk, voting_hash, 0, Chain.chain_state[pk].nonce + 1, 10, 0, %{choices: ["a", "b", "c"]}), 1)) #good vote
    {:ok, s3_tx} = Keys.sign_tx(a2pk, 10, Chain.chain_state[pk].nonce + 2, 10)
    miner_tokens_at_start = Chain.chain_state[pk].balance
    {:ok, v3} = Keys.sign_txdata(elem(TxData.create(a2pk, voting_hash, 0, 1, 10, 0, %{choices: ["b"]}), 1), a2sk) #good vote
    {:ok, v4} = Keys.sign_txdata(elem(TxData.create(a2pk, voting_hash, 0, 2, 10, 0, %{choices: ["c"]}), 1), a2sk) #double vote
    {:ok, v5} = Keys.sign_txdata(elem(TxData.create(a1pk, voting_hash, 0, 1, 10, 0, %{choices: ["a", "b", "a"]}), 1), a1sk) #choice used multiple times
    Pool.add_transaction(v2)
    Pool.add_transaction(s3_tx)
    Pool.add_transaction(v3)
    Pool.add_transaction(v4)
    Pool.add_transaction(v5)
    Miner.mine_sync_block_to_chain

    proper_end_state = %{voters: %{pk => true, a2pk => true}, results: %{"a" => miner_tokens_at_start, "b" => miner_tokens_at_start + 30, "c" => miner_tokens_at_start}}

    assert Chain.top_height == begin_height + 1 #voting has just closed
    assert Pool.get_and_empty_pool == tx_list_to_map([v4, v5])
    assert Enum.count(Chain.top_block.txs) == 4 #2 votes, 1 spend, 1 coinbase
    assert Chain.chain_state[voting_hash].state == proper_end_state
    {:ok, v6} = Keys.sign_txdata(elem(TxData.create(a1pk, voting_hash, 0, 2, 10, 0, %{choice: "c"}), 1), a1sk) #too late
    Pool.add_transaction(v6)
    Miner.mine_sync_block_to_chain
    assert Pool.get_and_empty_pool == tx_list_to_map([v6])
    assert Enum.count(Chain.top_block.txs) == 1 #1 coinbase
    assert Chain.chain_state[voting_hash].state == proper_end_state
  end

  defp tx_list_to_map(txs) do
    Enum.reduce(txs,
                %{},
                fn (tx, acc) ->
                  Map.put(acc, SignedTx.hash(tx), tx)
                end)
  end

end
