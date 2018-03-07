defmodule Aecore.Structures.VotingQuestionTx do
  alias Aecore.Structures.VotingQuestionTx

  require Logger

  @type t :: %VotingQuestionTx{
          question: String.t(),
          possible_answer_count: non_neg_integer(),
          answers: list(),
          start_block_height: non_neg_integer(),
          close_block_height: non_neg_integer()
        }

  defstruct [
    :question,
    :possible_answer_count,
    :answers,
    :start_block_height,
    :close_block_height
  ]

  use ExConstructor

  @spec create(
          String.t(),
          non_neg_integer(),
          list(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, VotingQuestionTx.t()}
  def create(
        question,
        possible_answer_count,
        answers,
        start_block_height,
        close_block_height
      ) do
    {:ok,
     %VotingQuestionTx{
       question: question,
       possible_answer_count: possible_answer_count,
       answers: answers,
       start_block_height: start_block_height,
       close_block_height: close_block_height
     }}
  end
end
