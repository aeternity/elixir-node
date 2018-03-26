defmodule Aehttpserver.Web.Notify do
  @moduledoc """
  Contains websocket communication functionality
  """

  alias Aeutil.Serialization
  alias Aewallet.Encoding
  alias Aehttpserver.Web.Endpoint
  alias Aecore.Structures.Account

  def broadcast_new_transaction_in_the_pool(tx) do
    if tx.data.sender != nil do
      Endpoint.broadcast!(
        "room:notifications",
        "new_tx:" <> Account.base58c_encode(tx.data.sender),
        %{"body" => Serialization.tx(tx, :serialize)}
      )
    end

    if tx.data.payload.receiver != nil do
      Endpoint.broadcast!(
        "room:notifications",
        "new_tx:" <> Account.base58c_encode(tx.data.payload.receiver),
        %{"body" => Serialization.tx(tx, :serialize)}
      )
    end

    Endpoint.broadcast!("room:notifications", "new_transaction_in_the_pool", %{
      "body" => Serialization.tx(tx, :serialize)
    })
  end

  def broadcast_new_block_added_to_chain_and_new_mined_tx(block) do
    Enum.each(block.txs, fn tx ->
      Endpoint.broadcast!("room:notifications", "new_mined_tx_everyone", %{
        "body" => Serialization.tx(tx, :serialize)
      })

      if tx.data.sender != nil do
        Endpoint.broadcast!(
          "room:notifications",
          "new_mined_tx:" <> Account.base58c_encode(tx.data.sender),
          %{"body" => Serialization.tx(tx, :serialize)}
        )
      end

      if tx.data.payload.receiver != nil do
        Endpoint.broadcast!(
          "room:notifications",
          "new_mined_tx:" <> Account.base58c_encode(tx.data.payload.receiver),
          %{"body" => Serialization.tx(tx, :serialize)}
        )
      end
    end)

    Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{
      "body" => Serialization.block(block, :serialize)
    })
  end
end
