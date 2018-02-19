defmodule Aeutil.ValidateVotingJsonSchema do
  def question() do
    %{
      "type" => "object",
      "required" => [
        "start_block_height",
        "question",
        "possible_answer_count",
        "from_acc",
        "fee",
        "close_block_height",
        "answers"
      ],
      "properties" => %{
        "start_block_height" => %{
          "type" => "integer",
          "minimum" => 0
        },
        "question" => %{
          "type" => "string"
        },
        "possible_answer_count" => %{
          "type" => "integer",
          "minimum" => 0
        },
        "from_acc" => %{
          "type" => "string"
        },
        "fee" => %{
          "type" => "integer",
          "minimum" => 0
        },
        "close_block_height" => %{
          "type" => "integer",
          "minimum" => 0
        },
        "answers" => %{
          "type" => "array",
          "items" => %{
            "type" => "string"
          }
        }
      }
    }
    |> ExJsonSchema.Schema.resolve()
  end

  def answer() do
    %{
      "type" => "object",
      "required" => ["answer", "fee", "from_acc", "hash_question"],
      "properties" => %{
        "answer" => %{
          "type" => "array",
          "items" => %{
            "type" => "string"
          }
        },
        "fee" => %{
          "type" => "integer",
          "minimum" => 0
        },
        "from_acc" => %{
          "type" => "string"
        },
        "hash_question" => %{
          "type" => "string"
        }
      }
    }
    |> ExJsonSchema.Schema.resolve()
  end
end
