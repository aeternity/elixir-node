defmodule Aecore.VotingPrototype.Validation do
  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.VotingQuestionTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @spec validate(SignedTx.t()) :: boolean()
  def validate(%SignedTx{data: data}) do
    process(data)
  end

  def validate(_data) do
    Logger.error("[Voting Validation] Unknown voting data structure!")
    false
  end

  @spec process(VotingTx.t()) :: boolean()
  defp process(%VotingTx{voting_payload: %VotingQuestionTx{} = data_question}) do
    if validate_num_answer_count(data_question.possible_answer_count, data_question.answers) &&
         validate_blocks_interval(
           data_question.start_block_height,
           data_question.close_block_height
         ) do
      true
    else
      false
    end
  end

  @spec process(VotingTx.t()) :: boolean()
  defp process(%VotingTx{voting_payload: %VotingAnswerTx{hash_question: hash}} = data_answer) do
    question = Chain.get_voting_question_by_hash(hash).data

    if validate_answer_with_answer_count(question, data_answer) &&
         validate_answer_belongs_to_answers(question, data_answer) do
      true
    else
      false
    end
  end

  @spec validate_num_answer_count(non_neg_integer, list(String.t())) :: boolean()
  defp validate_num_answer_count(possible_answer_count, answers) do
    if Enum.count(answers) >= possible_answer_count do
      true
    else
      Logger.error("Invalid possible_answer_count!")
      false
    end
  end

  @spec validate_blocks_interval(non_neg_integer, non_neg_integer) :: boolean()
  defp validate_blocks_interval(start_block_height, close_block_height) do
    if start_block_height < close_block_height and Chain.top_height() < close_block_height do
      true
    else
      Logger.error("Invalid block range!")
      false
    end
  end

  @spec validate_answer_with_answer_count(VotingTx.t(), VotingTx.t()) :: boolean()
  defp validate_answer_with_answer_count(
         %VotingTx{voting_payload: %VotingQuestionTx{} = data_question},
         %VotingTx{voting_payload: %VotingAnswerTx{} = data_answer}
       ) do
    if Enum.count(data_answer.answer) <= data_question.possible_answer_count do
      true
    else
      Logger.error("Invalid number of answers!")
      false
    end
  end

  @spec validate_answer_belongs_to_answers(VotingTx.t(), VotingTx.t()) :: boolean()
  defp validate_answer_belongs_to_answers(
         %VotingTx{voting_payload: %VotingQuestionTx{} = data_question},
         %VotingTx{voting_payload: %VotingAnswerTx{} = data_answer}
       ) do
    belongs? =
      for x <- data_answer.answer do
        Enum.member?(data_question.answers, x)
      end
      |> Enum.all?(fn x -> x == true end)

    if belongs? == true do
      true
    else
      Logger.error("The answer is not belong to the list of possible answers!")
      false
    end
  end
end
