defmodule Aehttpserver.Web.Notify do
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.OracleQueryTx
  alias Aeutil.Serialization
  alias Aecore.Structures.SignedTx
  alias Aehttpserver.Web.Endpoint
  alias Aecore.Structures.Account

  def broadcast_new_transaction_in_the_pool(tx) do
    broadcast_tx(tx, true)

    broadcast_tx(tx, false)

    Endpoint.broadcast!("room:notifications", "new_transaction_in_the_pool", %{
      "body" => SignedTx.serialize(tx)
    })
  end

  def broadcast_new_block_added_to_chain_and_new_mined_tx(block) do
    Enum.each(block.txs, fn tx ->
      Endpoint.broadcast!("room:notifications", "new_mined_tx_everyone", %{
        "body" => SignedTx.serialize(tx)
      })

      broadcast_tx(tx, true)
    end)

    Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{
      "body" => Serialization.block(block, :serialize)
    })
  end

  def broadcast_tx(tx, is_to_sender) do
    if is_to_sender do
      for sender <- tx.data.senders do
        Endpoint.broadcast!(
          "room:notifications",
          "new_tx:" <> Account.base58c_encode(sender),
          %{"body" => SignedTx.serialize(tx)}
        )
      end
    else
      case tx.data.payload do
        %SpendTx{} ->
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_tx:" <> Account.base58c_encode(tx.data.payload.receiver),
            %{"body" => SignedTx.serialize(tx)}
          )

        %OracleQueryTx{} ->
          Aehttpserver.Web.Endpoint.broadcast!(
            "room:notifications",
            "new_tx:" <> Account.base58c_encode(tx.data.payload.oracle_address),
            %{"body" => SignedTx.serialize(tx)}
          )

        _ ->
          :ok
      end
    end
  end
end
