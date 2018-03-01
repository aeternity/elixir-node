defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias __MODULE__
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aeutil.Bits
  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Structures.VotingQuestionTx
  require Logger


  @type hash_types :: :chainstate | :header | :txs

  @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
  def block(block, direction) do
    new_header = %{
      block.header
      | chain_state_hash: bech32_binary(block.header.chain_state_hash, :chainstate, direction),
        prev_hash: bech32_binary(block.header.prev_hash, :header, direction),
        txs_hash: bech32_binary(block.header.txs_hash, :txs, direction)
    }

    new_txs =
      Enum.map(block.txs, fn tx ->
        map_to_tx(tx, direction)
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
        %SignedTx{data: SpendTx.new(new_data), signature: new_signature}

      :voting_tx ->
        case tx.data do
          %VotingTx{voting_payload: %VotingQuestionTx{}} ->
            new_data = %{tx.data.voting_payload | from_acc: hex_binary(tx.data.voting_payload.from_acc, direction)}
            new_signature = hex_binary(tx.signature, direction)

            %SignedTx{
              data: %VotingTx{voting_payload: VotingQuestionTx.new(new_data)},
              signature: new_signature
            }

          %VotingTx{voting_payload: %VotingAnswerTx{}} ->
            new_data = %{
              tx.data.voting_payload
              | from_acc: hex_binary(tx.data.voting_payload.from_acc, direction),
                hash_question: hex_binary(tx.data.voting_payload.hash_question, direction)
            }

            new_signature = hex_binary(tx.signature, direction)

            %SignedTx{
              data: %VotingTx{voting_payload: VotingAnswerTx.new(new_data)},
              signature: new_signature
            }
        end

      _ ->
        Logger.error("Unidentified type")
    end
  end

  @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, direction) do
    new_data = %{
      tx.data
      | from_acc: hex_binary(tx.data.from_acc, direction),
        to_acc: hex_binary(tx.data.to_acc, direction)
    }

    new_signature = hex_binary(tx.signature, direction)
    %SignedTx{data: SpendTx.new(new_data), signature: new_signature}
  end

  @spec map_to_tx(map(), :serialize | :deserialize) :: SignedTx.t()
  def map_to_tx(map, direction) do
    case map do
      %{
        data: %{
          voting_payload: %{
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
        new_map = %{map.data.voting_payload | from_acc: hex_binary(map.data.voting_payload.from_acc, direction)}
        new_signature = hex_binary(map.signature, direction)
        %SignedTx{data: %VotingTx{voting_payload: VotingQuestionTx.new(new_map)}, signature: new_signature}

      %{
        data: %{voting_payload: %{hash_question: _, answer: _, from_acc: _, fee: _, nonce: _}},
        signature: _
      } ->
        new_map = %{
          map.data.voting_payload
          | from_acc: hex_binary(map.data.voting_payload.from_acc, direction),
            hash_question: hex_binary(map.data.voting_payload.hash_question, direction)
        }

        new_signature = hex_binary(map.signature, direction)
        %SignedTx{data: %VotingTx{voting_payload: VotingAnswerTx.new(new_map)}, signature: new_signature}

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
        %SignedTx{data: SpendTx.new(new_map), signature: new_signature}
    end
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
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

  @spec bech32_binary(binary() | String.t, Serialization.hash_types(),
                      :serialize | :deserialize) :: String.t() | binary()
  def bech32_binary(data, hash_type, direction) do
    case direction do
      :serialize ->
        case hash_type do
          :header ->
            Header.bech32_encode(data)
          :txs ->
            SignedTx.bech32_encode_root(data)
          :chainstate ->
            ChainState.bech32_encode(data)
        end
      :deserialize ->
        Bits.bech32_decode(data)
    end
  end

  @spec base64_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
  def base64_binary(data, direction) do
    if data != nil do
      case(direction) do
        :serialize ->
          Base.encode64(data)
        :deserialize ->
          Base.decode64!(data)
      end
    else
      nil
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

  @spec pack_binary(term()) :: map()
  def pack_binary(term) do
    case term do
      %Block{} ->
        Map.from_struct(%{term | header: Map.from_struct(term.header)})
      %SignedTx{} ->
        Map.from_struct(%{term | data: Map.from_struct(term.data)})
      %VotingTx{} ->
        Map.put(Map.from_struct(term), :voting_payload, Map.from_struct(term.voting_payload))
      %{__struct__: _} ->
        Map.from_struct(term)
      _ ->
        term
    end
    |> Msgpax.pack!(iodata: false)
  end
end
