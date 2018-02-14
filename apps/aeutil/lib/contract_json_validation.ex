defmodule Aeutil.ValidateContractJsonSchema do

  def proposal() do
    %{
      "type" => "object",
      "required" => ["contract_hash", "participants", "ttl", "fee"],
      "properties" => %{
        "contract_hash" => %{
      "type" => "string"
    },
        "participants" => %{
          "type" => "array",
          "uniqueItems" => true,
          "items" => %{
            "type" => "string"
            }
        },
        "ttl" => %{
          "type" => "integer",
          "minimum" => 10
        },
        "fee" => %{
          "type" => "integer",
          "minimum" => 0
        }
      }
    } |> ExJsonSchema.Schema.resolve
  end

  def signing() do
    %{
      "type" => "object",
      "required" => ["signature", "pubkey", "contract_hash", "fee"],
      "properties" => %{
        "signature" => %{
      "type" => "string"
    },
        "pub_key" => %{
          "type" => "string"
        },
        "contract_hash" => %{
          "type" => "string"
        },
        "fee" => %{
          "type" => "integer",
          "minimum" => 0
        }
      }
    } |> ExJsonSchema.Schema.resolve
  end
  end
