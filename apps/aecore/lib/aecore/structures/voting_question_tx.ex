defmodule Aecore.Structures.VotingQuestionTx do
  alias Aecore.Structures.VotingQuestionTx

  require Logger

  @type t :: %VotingQuestionTx{
    question: String.t(),
    possible_answer_count: non_neg_integer(),
    answers: list(),
    from_acc: binary(),
    start_block_height: non_neg_integer(),
    close_block_height: non_neg_integer(),
    fee: non_neg_integer()
  }

  defstruct [:question,
             :possible_answer_count,
             :answers,
             :from_acc,
             :start_block_height,
             :close_block_height,
             :fee
            ]
  use ExConstructor

  def create(question, possible_answer_count, answers, from_acc, start_block_height, close_block_height, fee) do
    {:ok, %VotingQuestionTx{question: question,
                            possible_answer_count: possible_answer_count,
                            answers: answers,
                            from_acc: from_acc,
                            start_block_height: start_block_height,
                            close_block_height: close_block_height,
                            fee: fee}}
  end

end
