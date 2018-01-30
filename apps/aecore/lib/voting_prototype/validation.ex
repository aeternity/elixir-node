defmodule Aecore.VotingPrototype.Validation do

  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.VotingQuestionTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @spec validate(VotingTx.t()) :: boolean()
  def validate(%VotingTx{data: data}) do
    process(data)
  end

  def validate(_data) do
    Logger.error("[Voting Validation] Unknown voting data structure!")
    false
  end

  @spec process(VotingQuestionTx.t()) :: boolean()
  defp process(%VotingQuestionTx{} = data_question) do
    if string_validation(data_question.question) &&
       possible_answer_count(data_question.possible_answer_count) &&
       list_validation(data_question.answers) &&
       binary_validation_from_acc(data_question.from_acc) &&
       start_block_height_validation(data_question.start_block_height) &&
       close_block_height_validation(data_question.close_block_height) &&
       fee_validation(data_question.fee) &&
       validate_num_answer_count(data_question.possible_answer_count,
        data_question.answers) &&
       validate_blocks_interval(data_question.start_block_height,
        data_question.close_block_height) do
      true
    else
      false
    end
  end

  @spec process(VotingAnswerTx) :: boolean()
  defp process(%VotingAnswerTx{hash_question: hash} = data_answer) do
    question = Chain.get_voting_question_by_hash(hash).data
    if binary_validation_hash_question(data_answer.hash_question) &&
       list_validation(data_answer.answer) &&
       binary_validation_from_acc(data_answer.from_acc) &&
       fee_validation(data_answer.fee) &&
       validate_answer_with_answer_count(question, data_answer) &&
       validate_answer_belongs_to_answers(question, data_answer) do
      true
    else
      false
    end
  end

  @spec string_validation(String.t()) :: boolean()
  defp string_validation(data) do
    if String.valid?(data) do
      true
    else
      Logger.error("Invalid question format!")
      false
    end
  end

  @spec possible_answer_count(non_neg_integer()) :: boolean()
  defp possible_answer_count(data) do
    if is_integer(data) and data > 0 do
      true
    else
      Logger.error("Invalid possible answer count!")
      false
    end
  end

  @spec list_validation(list(String.t())) :: boolean()
  defp list_validation(data) do
    case is_list(data) && !Enum.empty?(data)  do
      true -> each_element_is_string_in_the_list(data)
      false -> Logger.error("Invalid answer list type!")
        false
    end
  end

  @spec binary_validation_from_acc(binary()) :: boolean()
  defp binary_validation_from_acc(data) do
    if is_binary(data) do
      true
    else
      Logger.error("Invalid public key!")
      false
    end
  end

  @spec start_block_height_validation(non_neg_integer()) :: boolean()
  defp start_block_height_validation(data) do
    if is_integer(data) and data > 0 do
      true
    else
      Logger.error("Invalid start block height!")
      false
    end
  end

  @spec close_block_height_validation(non_neg_integer()) :: boolean()
  defp close_block_height_validation(data) do
    if is_integer(data) and data > 0 do
      true
    else
      Logger.error("Invalid close block height!")
      false
    end
  end

  @spec fee_validation(non_neg_integer()) :: boolean()
  defp fee_validation(data) do
    if is_integer(data) and data > 0 do
      true
    else
      Logger.error("Invalid fee!")
      false
    end
  end

  @spec binary_validation_hash_question(binary()) :: boolean()
  defp binary_validation_hash_question(data) do
    if is_binary(data) do
      true
    else
      Logger.error("Invalid hash question!")
      false
    end
  end

  @spec each_element_is_string_in_the_list(list()) :: boolean()
  defp each_element_is_string_in_the_list(data) do
    case Enum.all?(data, fn(x) -> String.valid?(x) == true end)  do
      true -> true
      false -> Logger.error("Invalid answer list!")
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
    if start_block_height < close_block_height do
      true
    else
      Logger.error("Invalid block range!")
      false
    end
  end

  @spec validate_answer_with_answer_count(VotingQuestionTx.t(),
                                          VotingAnswerTx.t()) :: boolean()
  defp validate_answer_with_answer_count(%VotingQuestionTx{} = data_question,
                                         %VotingAnswerTx{} = data_answer) do
    if Enum.count(data_answer.answer) <= data_question.possible_answer_count  do
      true
    else
      Logger.error("Invalid number of answers!")
      false
    end
  end

  @spec validate_answer_belongs_to_answers(VotingQuestionTx.t(),
                                           VotingAnswerTx.t()) :: boolean()
  defp validate_answer_belongs_to_answers(%VotingQuestionTx{} = data_question,
                                          %VotingAnswerTx{} = data_answer) do
    is_belongs = for x <- data_answer.answer do
      Enum.member?(data_question.answers, x)
    end
    |> Enum.all?(fn(x) -> x == true end)

    if is_belongs == true do
      true
    else
      Logger.error("The answer is not belong to the list of possible answers!")
      false
    end
  end
end
