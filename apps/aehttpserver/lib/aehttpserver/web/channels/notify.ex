defmodule Aehttpserver.Web.Notify do

  alias Aeutil.Serialization
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.VotingTx
  alias Aehttpserver.Web.Endpoint
  alias Aecore.Structures.SpendTx

  def broadcast_new_transaction_in_the_pool(tx) do
    case tx do
      %SignedTx{data: %VotingTx{}} ->
        if tx.data.from_acc != nil do
          Endpoint.broadcast!(
            "room:notifications",
            "new_voting_tx:" <> Base.encode16(tx.data.from_acc),
            %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
          )
        end

        Endpoint.broadcast!(
          "room:notifications",
          "new_voting_transaction_in_the_pool",
          %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
        )

      %SignedTx{data: %SpendTx{}} ->
        if tx.data.from_acc != nil do
          Endpoint.broadcast!(
            "room:notifications",
            "new_spend_tx:" <> Base.encode16(tx.data.from_acc),
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )
        end

        if tx.data.to_acc != nil do
          Endpoint.broadcast!(
            "room:notifications",
            "new_spend_tx:" <> Base.encode16(tx.data.to_acc),
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )
        end

        Endpoint.broadcast!(
          "room:notifications",
          "new_spend_transaction_in_the_pool",
          %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
        )
    end
  end

  def broadcast_new_block_added_to_chain_and_new_mined_tx(block) do
    Enum.each(block.txs, fn tx ->
      case tx do
        %SignedTx{data: %VotingTx{}} ->
          Endpoint.broadcast!(
            "room:notifications",
            "new_mined_voting_tx_everyone",
            %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
          )

          if tx.data.from_acc != nil do
            Endpoint.broadcast!(
              "room:notifications",
              "new_mined_voting_tx:" <> Base.encode16(tx.data.from_acc),
              %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
            )
          end

        %SignedTx{data: %SpendTx{}} ->
          Endpoint.broadcast!(
            "room:notifications",
            "new_mined_spend_tx_everyone",
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )

          if tx.data.from_acc != nil do
            Endpoint.broadcast!(
              "room:notifications",
              "new_mined_spend_tx:" <> Base.encode16(tx.data.from_acc),
              %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
            )
          end

          if tx.data.to_acc != nil do
            Endpoint.broadcast!(
              "room:notifications",
              "new_mined_spend_tx:" <> Base.encode16(tx.data.to_acc),
              %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
            )
          end
      end
    end)

    Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{
      "body" => Serialization.block(block, :serialize)
    })
  end
end
