defmodule Aehttpserver.Web.VotingController do
  require Logger
  use Aehttpserver.Web, :controller

  alias Aecore.VotingPrototype.Manager
  alias Aeutil.Serialization
  alias Aecore.Chain.Worker
  alias Aecore.Structures.VotingQuestionTx
  alias Aeutil.ValidateVotingJsonSchema, as: Schema

  ## API

  def voting_request(conn, params) do
    [_ | request] = conn.path_info

    case request do
      [command, type] when command == "register"
      and type == "question" or type == "answer" ->

        case ExJsonSchema.Validator.validate(get_schema(type), params) do
          :ok ->
            data = convert_and_serialize_binary_fields(params, String.to_atom(type))
            json(conn, register_and_respond(data, String.to_atom(type)))

          {:error, reason} ->
            reason_list = for {x, y} <- reason do [x, y] end
            json(conn, build_json_response("#{command}_#{type}",
                  "error", reason_list))
        end

        _ ->
        json(conn, build_json_response("unknown",
              "error", "unknown request"))
    end
  end

  def show_registered_questions(conn, _params) do
    questions = Worker.all_registered_voting_questions()

    questions =
      Enum.reduce(questions, %{}, fn {question_hash, value_map}, acc ->
        Map.put(acc, Base.encode16(question_hash), %{
          answers: value_map.answers,
          data: %VotingQuestionTx{
            answers: value_map.data.answers,
            close_block_height: value_map.data.close_block_height,
            fee: value_map.data.fee,
            from_acc: Base.encode16(value_map.data.from_acc),
            possible_answer_count: value_map.data.possible_answer_count,
            question: value_map.data.question,
            start_block_height: value_map.data.start_block_height
          },
          result: value_map.result
        })
      end)

    json(conn, build_json_response("show_registered questions", "ok", questions))

  end

  defp register_and_respond(tx, type) when type == :answer or type == :question do
    handler = registration_handler(type)
    case handler.(tx) do
      :ok ->
        build_json_response("register_#{Atom.to_string(type)}", "ok",
          "registered #{Atom.to_string(type)}")
      reason ->
        Logger.error("[error] Invalid given type")
        build_json_response("register_#{Atom.to_string(type)}", "error", "reason ???")
    end
  end

  defp convert_and_serialize_binary_fields(tx, type) do

    case type do
      :answer ->
        tx = Serialization.convert_map_keys(tx, :to_atom)
        %{tx | from_acc: Serialization.hex_binary(tx.from_acc, :deserialize),
          hash_question: Serialization.hex_binary(tx.hash_question, :deserialize)}
      :question ->
        tx = Serialization.convert_map_keys(tx, :to_atom)
        %{tx | from_acc: Serialization.hex_binary(tx.from_acc, :deserialize)}

        _ ->
        Logger.error("[error] Invalid given type")
        build_json_response("unknown", "error", "unknown type to serialize")
    end
  end

  defp build_json_response(command, status, response) do
    %{"command"  => command,
      "status"   => status,
      "response" => response}
  end

  defp get_schema("question"), do: Schema.question()
  defp get_schema("answer"), do: Schema.answer()

  defp registration_handler(:question), do: &Manager.register_question/1
  defp registration_handler(:answer), do: &Manager.register_answer/1


end
