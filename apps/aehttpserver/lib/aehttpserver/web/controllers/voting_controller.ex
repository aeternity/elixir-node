defmodule Aehttpserver.Web.VotingController do
  require Logger
  use Aehttpserver.Web, :controller

  alias Aecore.VotingPrototype.Manager
  alias Aeutil.Serialization
  alias Aecore.Chain.Worker
  alias Aeutil.ValidateVotingJsonSchema, as: Schema

  def voting_request(conn, params) do
    [_h | t] = conn.path_info
    request = t
    case request do
      ["register", "question"] -> 
        schema = Schema.question
        case ExJsonSchema.Validator.validate(schema, params) do
          :ok ->
            if params["start_block_height"] >= Aecore.Chain.Worker.top_height do
            question = convert_and_serialize_binary_fields(params, :question)
            json(conn, register_and_respond(question, :question))
            else
            json(conn, %{"command" => "Register question", "status" => "Error",
                         "response" => "Error, Invalid start_block_height"})
            end
          {:error, reason} ->
              reason_list = for {x, y} <- reason, do: [x, y]
              json(conn, %{"command"=> "Register question", "status" => "Error", 
                           "response" => reason_list})   
        end 
      ["register", "answer"] ->      
        schema = Schema.answer
        case ExJsonSchema.Validator.validate(schema, params) do
          :ok ->
            answer = convert_and_serialize_binary_fields(params,:answer)
            answers_question_close_block_height = 
            Aecore.Chain.Worker.get_voting_question_by_hash(answer.hash_question).data.close_block_height 
            if answers_question_close_block_height >= Aecore.Chain.Worker.top_height do
            json(conn, register_and_respond(answer, :answer))
            else 
            json(conn, %{"command" => "Register answer", "status" => "Error",
                         "response" => "Error, Voting is over"})
            end  
          {:error, reason} ->
            reason_list = for {x, y} <- reason, do: [x, y]
            json(conn, %{"command"=> "Register answer", "status" => "Error", 
                         "response" => reason_list})
        end 
           _ -> json(conn, %{"command" => "Register answer", "status" => "Error",
                             "response" => "Error, Invalid answer voting request"})
    end
  end


  def show_registered_questions(conn,_params) do
    questions =  Worker.all_registered_voting_questions
    questions =
      Enum.reduce(questions, %{}, fn({question_hash, value_map}, acc) ->
        Map.put(acc, Base.encode16(question_hash),
     %{answers: value_map.answers,
      data: %Aecore.Structures.VotingQuestionTx{
        answers: value_map.data.answers,
        close_block_height: value_map.data.close_block_height,
        fee: value_map.data.fee,
        from_acc: Base.encode16(value_map.data.from_acc),
        possible_answer_count: value_map.data.possible_answer_count,
        question: value_map.data.question,
        start_block_height: value_map.data.start_block_height},
      result: value_map.result}) end)
    json(conn, %{"command" => "Get registered questions", "status" => "ok",
                 "response" => questions})
  end

  defp register_and_respond(tx,type) do
    case type do
      :answer -> 
        case Manager.register_answer tx do
          :ok -> %{"command" => "Register answer","status" => "Ok",
                   "response" => "Registered answer"}
          _ -> %{"command" => "Register answer","status" => "Error",
                 "response" => "Couldn't register an answer"}
        end
      :question ->
        case Manager.register_question tx do
          :ok -> %{"command" => "Register question","status" => "Ok",
                   "response" => "Registered question"}
          _ -> %{"command" => "Register question", "status" => "Error", 
                 "response" => "Couldn't register a question"}
        end
      _ -> Logger.error "[error] Invalid given type"
    end
  end

  defp convert_and_serialize_binary_fields(tx,type)do
    case type do
      :answer -> 
        tx = Serialization.convert_map_keys(tx, :to_atom)
        %{tx | from_acc: Serialization.hex_binary(tx.from_acc, :deserialize),
               hash_question: Serialization.hex_binary(tx.hash_question, :deserialize)}
      :question -> 
        tx = Serialization.convert_map_keys(tx, :to_atom)
        %{tx | from_acc: Serialization.hex_binary(tx.from_acc, :deserialize)}
      _ -> Logger.error "[error] Invalid given type"
    end
  end

end
