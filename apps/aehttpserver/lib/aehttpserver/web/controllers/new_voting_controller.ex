defmodule Aehttpserver.Web.VotingController do
  use Aehttpserver.Web, :controller

  alias Aecore.VotingPrototype.Validation
  alias Aecore.VotingPrototype.Manager
  alias Aeutil.Serialization
  alias Aecore.Chain.Worker

  def new_question(conn, _params) do
    question = Serialization.convert_map_keys(conn.body_params, :to_atom)
    bin_from_acc = Serialization.hex_binary(question.from_acc, :deserialize)
    question = %{question | from_acc: bin_from_acc}
    response =
    case Manager.register_question question do
      :ok -> :ok
      _ -> :error
    end
    json(conn, Poison.encode!(%{"registered_question" => to_string response}))
  end

  def new_answer(conn, _params) do
    answer = Serialization.convert_map_keys(conn.body_params, :to_atom)
    bin_from_acc = Serialization.hex_binary(answer.from_acc, :deserialize)
    bin_hash_question = Serialization.hex_binary(answer.hash_question, :deserialize)
    answer = %{answer | from_acc: bin_from_acc,
                        hash_question: bin_hash_question}
    response =
    case Manager.register_answer answer do 
      :ok -> :ok
      _ -> :error
    end 
    json(conn, Poison.encode!(%{"registered_answer" => to_string response}))
  end

  def show_registered_questions(conn,_params) do
    questions =  Worker.all_registered_voting_questions
    questions = Enum.reduce(questions, %{}, fn({question_hash, value_map}, acc) -> Map.put(acc, Base.encode16(question_hash),
     %{answers: value_map.answers,
      data: %Aecore.Structures.VotingQuestionTx{answers: value_map.data.answers, close_block_height: value_map.data.close_block_height, fee: value_map.data.fee,
      from_acc: Base.encode16(value_map.data.from_acc),
      possible_answer_count: value_map.data.possible_answer_count, question: value_map.data.question, start_block_height: value_map.data.start_block_height},
      result: value_map.result}) end)  
    json(conn,Poison.encode!(questions))
  end

end
