defmodule Aehttpserver.Web.Notify do
  alias Aeutil.Serialization

  def broadcast_new_transaction_in_the_pool(tx) do
    case tx do
      %Aecore.Structures.SignedTx{data: %Aecore.Structures.VotingTx{}} ->
        if tx.data.data.from_acc != nil do
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_voting_tx:" <> Base.encode16(tx.data.data.from_acc),
            %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
          )
        end

        Aehttpserver.Web.Endpoint.broadcast!(
          "room:notifications",
          "new_voting_transaction_in_the_pool",
          %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
        )

      %Aecore.Structures.SignedTx{data: %Aecore.Structures.SpendTx{}} ->
        if tx.data.from_acc != nil do
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_spend_tx:" <> Base.encode16(tx.data.from_acc),
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )
        end

        if tx.data.to_acc != nil do
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_spend_tx:" <> Base.encode16(tx.data.to_acc),
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )
        end

        Aehttpserver.Web.Endpoint.broadcast!(
          "room:notifications",
          "new_spend_transaction_in_the_pool",
          %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
        )
    end
  end

  def broadcast_new_block_added_to_chain_and_new_mined_tx(block) do
    Enum.each(block.txs, fn tx ->
      case tx do
        %Aecore.Structures.SignedTx{data: %Aecore.Structures.VotingTx{}} ->
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_mined_voting_tx_everyone",
            %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
          )

          if tx.data.data.from_acc != nil do
            Aehttpserver.Web.Endpoint.broadcast!(
              "room:notifications",
              "new_mined_voting_tx:" <> Base.encode16(tx.data.data.from_acc),
              %{"body" => Serialization.tx(tx, :voting_tx, :serialize)}
            )
          end

        %Aecore.Structures.SignedTx{data: %Aecore.Structures.SpendTx{}} ->
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_mined_spend_tx_everyone",
            %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
          )

          if tx.data.from_acc != nil do
            Aehttpserver.Web.Endpoint.broadcast!(
              "room:notifications",
              "new_mined_spend_tx:" <> Base.encode16(tx.data.from_acc),
              %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
            )
          end

          if tx.data.to_acc != nil do
            Aehttpserver.Web.Endpoint.broadcast!(
              "room:notifications",
              "new_mined_spend_tx:" <> Base.encode16(tx.data.to_acc),
              %{"body" => Serialization.tx(tx, :spend_tx, :serialize)}
            )
          end
      end
    end)

    Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{
      "body" => Serialization.block(block, :serialize)
    })
  end
end
