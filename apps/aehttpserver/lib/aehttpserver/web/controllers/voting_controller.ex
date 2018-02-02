defmodule Aehttpserver.Web.VotingController do
  use Aehttpserver.Web, :controller

  alias Aecore.VotingPrototype.Validation
  alias Aecore.VotingPrototype.Manager
  alias Aeutil.Serialization
  alias Aecore.Chain.Worker

  def voting_request(conn, params) do
    [h|t] = conn.path_info
    request = t 
    case request do
    ["new_voting","question"] -> 
          question = Serialization.convert_map_keys(params, :to_atom)
          bin_from_acc = Serialization.hex_binary(question.from_acc, :deserialize)
          question = %{question | from_acc: bin_from_acc}
          case Manager.register_question question do
            :ok -> json(conn, %{"Registered question status" => "ok"})
            _ -> json(conn, %{"Registered question status" => "Invalid question voting request"})
          end
    ["new_voting","answer"] ->  
        answer = Serialization.convert_map_keys(params, :to_atom)
        bin_from_acc = Serialization.hex_binary(answer.from_acc, :deserialize)
        bin_hash_question = Serialization.hex_binary(answer.hash_question, :deserialize)
        answer = %{answer | from_acc: bin_from_acc,
                            hash_question: bin_hash_question}
        case Manager.register_answer answer do 
          :ok -> json(conn, %{"Registered answer status" => "ok"})
          _ -> json(conn, %{"Registered answer status" => "Invalid voting answer request"})
        end
      _ -> json(conn, %{"Registered answer status" => "Invalid answer voting request"})
    end
  end

  def show_registered_questions(conn,_params) do
    questions =  Worker.all_registered_voting_questions
    questions = Enum.reduce(questions, %{}, fn({question_hash, value_map}, acc) -> Map.put(acc, Base.encode16(question_hash),
     %{answers: value_map.answers,
      data: %Aecore.Structures.VotingQuestionTx{answers: value_map.data.answers, close_block_height: value_map.data.close_block_height, fee: value_map.data.fee,
      from_acc: Base.encode16(value_map.data.from_acc),
      possible_answer_count: value_map.data.possible_answer_count, question: value_map.data.question, start_block_height: value_map.data.start_block_height},
      result: value_map.result}) end)  
    json(conn, questions)
  end

end
