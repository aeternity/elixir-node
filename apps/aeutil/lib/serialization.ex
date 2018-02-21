defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Structures.VotingQuestionTx
  require Logger

  @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
  def block(block, direction) do
    new_header = %{
      block.header
      | chain_state_hash: hex_binary(block.header.chain_state_hash, direction),
        prev_hash: hex_binary(block.header.prev_hash, direction),
        txs_hash: hex_binary(block.header.txs_hash, direction)
    }

    new_txs =
      Enum.map(block.txs, fn tx ->
        case tx do
          %Aecore.Structures.SignedTx{data: %Aecore.Structures.VotingTx{}} ->
            tx(tx, :voting_tx, direction)

          %Aecore.Structures.SignedTx{data: %Aecore.Structures.TxData{}} ->
            tx(tx, :spend_tx, direction)
        end
      end)

    Block.new(%{block | header: Header.new(new_header), txs: new_txs})
  end

  @spec tx(SignedTx.t(), atom(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, type, direction) do
    case type do
      :spend_tx ->
        new_data = %{
          tx.data
          | from_acc: hex_binary(tx.data.from_acc, direction),
            to_acc: hex_binary(tx.data.to_acc, direction)
        }

        new_signature = hex_binary(tx.signature, direction)
        %SignedTx{data: TxData.new(new_data), signature: new_signature}

      :voting_tx ->
        case tx.data do
          %Aecore.Structures.VotingTx{data: %Aecore.Structures.VotingQuestionTx{}} ->
            new_data = %{tx.data.data | from_acc: hex_binary(tx.data.data.from_acc, direction)}
            new_signature = hex_binary(tx.signature, direction)

            %SignedTx{
              data: %VotingTx{data: VotingQuestionTx.new(new_data)},
              signature: new_signature
            }

          %Aecore.Structures.VotingTx{data: %Aecore.Structures.VotingAnswerTx{}} ->
            new_data = %{
              tx.data.data
              | from_acc: hex_binary(tx.data.data.from_acc, direction),
                hash_question: hex_binary(tx.data.data.hash_question, direction)
            }

            new_signature = hex_binary(tx.signature, direction)

            %SignedTx{
              data: %VotingTx{data: VotingAnswerTx.new(new_data)},
              signature: new_signature
            }
        end

      _ ->
        Logger.error("Unidentified type")
    end
  end

  def map_to_tx(map, direction) do
    case map do
      %{
        data: %{
          data: %{
            question: _,
            possible_answer_count: _,
            answers: _,
            from_acc: _,
            start_block_height: _,
            close_block_height: _,
            fee: _,
            nonce: _
          }
        },
        signature: _
      } ->
        new_map = %{map.data.data | from_acc: hex_binary(map.data.data.from_acc, direction)}
        new_signature = hex_binary(map.signature, direction)
        %SignedTx{data: %VotingTx{data: VotingQuestionTx.new(new_map)}, signature: new_signature}

      %{
        data: %{data: %{hash_question: _, answer: _, from_acc: _, fee: _, nonce: _}},
        signature: _
      } ->
        new_map = %{
          map.data.data
          | from_acc: hex_binary(map.data.data.from_acc, direction),
            hash_question: hex_binary(map.data.data.hash_question, direction)
        }

        new_signature = hex_binary(map.signature, direction)
        %SignedTx{data: %VotingTx{data: VotingAnswerTx.new(new_map)}, signature: new_signature}

      %{
        data: %{from_acc: _, to_acc: _, value: _, nonce: _, fee: _, lock_time_block: _},
        signature: _
      } ->
        new_map = %{
          map.data
          | from_acc: hex_binary(map.data.from_acc, direction),
            to_acc: hex_binary(map.data.to_acc, direction)
        }

        new_signature = hex_binary(map.signature, direction)
        %SignedTx{data: TxData.new(new_map), signature: new_signature}
    end
  end

  # @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  # def tx(tx, direction) do
  #   new_data = %{tx.data |
  #                from_acc: hex_binary(tx.data.from_acc, direction),
  #                to_acc: hex_binary(tx.data.to_acc, direction)}
  #   new_signature = hex_binary(tx.signature, direction)
  #   %SignedTx{data: TxData.new(new_data), signature: new_signature}
  # end

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
  def hex_binary(data, direction) do
    if data != nil do
      case direction do
        :serialize ->
          Base.encode16(data)

        :deserialize ->
          Base.decode16!(data)
      end
    else
      nil
    end
  end

  def convert_map_keys(map, type) do
    case type do
      :to_atom ->
        Map.new(map, fn {k, v} ->
          if !is_atom(k) do
            {String.to_atom(k), v}
          else
            {k, v}
          end
        end)

      :to_string ->
        Map.new(map, fn {k, v} ->
          if is_atom(k) do
            {Kernel.to_string(k), v}
          else
            {k, v}
          end
        end)
    end
  end

  def merkle_proof(proof, acc) when is_tuple(proof) do
    proof
    |> Tuple.to_list()
    |> merkle_proof(acc)
  end

  def merkle_proof([], acc), do: acc

  def merkle_proof([head | tail], acc) do
    if is_tuple(head) do
      merkle_proof(Tuple.to_list(head), acc)
    else
      acc = [hex_binary(head, :serialize) | acc]
      merkle_proof(tail, acc)
    end
  end
end
