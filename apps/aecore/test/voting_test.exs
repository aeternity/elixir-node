defmodule VotingTest do
  @moduledoc """
  Unit test for the voting
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.VotingQuestionTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Structures.VotingTx

  setup do
    Pool.start_link([])
    []
  end

  # @tag timeout: 30_000
  # @tag :voting
  # test "Valid question with valid answer" do
  #   {hash_q, sign_tx} = valid_question_tx()
  #   :ok = Pool.add_transaction(sign_tx)
  #   :ok = Miner.mine_sync_block_to_chain
  #   {_hash_a, sign_tx_a} = valid_answer_tx(hash_q)
  #   :ok = Pool.add_transaction(sign_tx_a)
  #   :ok = Miner.mine_sync_block_to_chain
  #   assert %{["yes"] => _} = Chain.get_voting_result_for_a_question(hash_q)
  # end
  #
  # @tag timeout: 30_000
  # @tag :voting
  # test "Valid question with invalid answer" do
  #   {hash_q, sign_tx} = valid_question_tx()
  #   :ok = Pool.add_transaction(sign_tx)
  #   :ok = Miner.mine_sync_block_to_chain
  #   {_hash_a, sign_tx_a} = invalid_answer_tx(hash_q)
  #   :error = Pool.add_transaction(sign_tx_a)
  #   :ok = Miner.mine_sync_block_to_chain
  #   assert %{} == Chain.get_voting_result_for_a_question(hash_q)
  # end
  #
  # @tag timeout: 30_000
  # @tag :voting
  # test "Invalid question" do
  #   {hash_q, sign_tx} = invalid_question_tx()
  #   :error = Pool.add_transaction(sign_tx)
  #   :ok = Miner.mine_sync_block_to_chain
  #   assert nil == Chain.get_voting_question_by_hash(hash_q)
  # end

  defp valid_question_tx() do
    pubkey = elem(Keys.pubkey(), 1)
    q = %{question: "Is it raining?",
          possible_answer_count: 1,
          answers: ["yes", "no"],
          from_acc: pubkey,
          start_block_height: Chain.top_height,
          close_block_height: Chain.top_height + 10,
          fee: 10,
          nonce: Map.get(Aecore.Chain.Worker.chain_state, pubkey, %{nonce: 0}).nonce + 1}

    voting_tx = %VotingTx{voting_payload: struct!(VotingQuestionTx, q)}
    {:ok, signature} = Keys.sign(voting_tx)
    sign_tx = %SignedTx{data: voting_tx, signature: signature}
    hash = SignedTx.hash_tx(sign_tx)
    {hash, sign_tx}
  end

  defp invalid_question_tx() do
    pubkey = elem(Keys.pubkey(), 1)
    q = %{question: "Choose your favorites colors?",
          possible_answer_count: 4,
          answers: ["black", "white", "red", "blue"],
          from_acc: pubkey,
          start_block_height: Chain.top_height + 1,
          close_block_height: Chain.top_height,
          fee: 10,
          nonce: Map.get(Aecore.Chain.Worker.chain_state, pubkey, %{nonce: 0}).nonce + 1}

    voting_tx = %VotingTx{voting_payload: struct!(VotingQuestionTx, q)}
    {:ok, signature} = Keys.sign(voting_tx)
    sign_tx = %SignedTx{data: voting_tx, signature: signature}
    hash = SignedTx.hash_tx(sign_tx)
    {hash, sign_tx}
  end

  defp valid_answer_tx(hash_q) do
    pubkey = elem(Keys.pubkey(), 1)
    a = %{hash_question: hash_q,
          answer: ["yes"],
          from_acc: pubkey,
          fee: 10,
          nonce: Map.get(Aecore.Chain.Worker.chain_state, pubkey, %{nonce: 0}).nonce + 1}

    voting_tx = %VotingTx{voting_payload: struct!(VotingAnswerTx, a)}
    {:ok, signature} = Keys.sign(voting_tx)
    sign_tx = %SignedTx{data: voting_tx, signature: signature}
    hash = SignedTx.hash_tx(sign_tx)
    {hash, sign_tx}
  end

  defp invalid_answer_tx(hash_q) do
    pubkey = elem(Keys.pubkey(), 1)
    a = %{hash_question: hash_q,
          answer: ["maybe"],
          from_acc: pubkey,
          fee: 10,
          nonce: Map.get(Aecore.Chain.Worker.chain_state, pubkey, %{nonce: 0}).nonce + 1}

    voting_tx = %VotingTx{voting_payload: struct!(VotingAnswerTx, a)}
    {:ok, signature} = Keys.sign(voting_tx)
    sign_tx = %SignedTx{data: voting_tx, signature: signature}
    hash = SignedTx.hash_tx(sign_tx)
    {hash, sign_tx}
  end
end
