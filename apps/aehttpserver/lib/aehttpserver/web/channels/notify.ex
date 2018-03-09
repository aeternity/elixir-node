defmodule Aehttpserver.Web.Notify do
  alias Aeutil.Serialization
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aehttpserver.Web.Endpoint

  def broadcast_new_transaction_in_the_pool(tx) do
    if match?(%SpendTx{}, tx.data) do
      broadcast_spend_tx(tx)
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

      case tx.data do
        %SpendTx{} ->
          broadcast_spend_tx(tx)

        _oracle_tx ->
          broadcast_oracle_tx(tx)
      end
    end)

    Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{
      "body" => Serialization.block(block, :serialize)
    })
  end

  def broadcast_spend_tx(tx) do
    if tx.data.from_acc != nil do
      Endpoint.broadcast!(
        "room:notifications",
        "new_mined_tx:" <> Base.encode16(tx.data.from_acc),
        %{"body" => Serialization.tx(tx, :serialize)}
      )
    end

    if tx.data.to_acc != nil do
      Endpoint.broadcast!(
        "room:notifications",
        "new_mined_tx:" <> Base.encode16(tx.data.to_acc),
        %{"body" => Serialization.tx(tx, :serialize)}
      )
    end
  end

  def broadcast_oracle_tx(tx) do
    case tx.data do
      %OracleRegistrationTxData{} ->
        Endpoint.broadcast!("room:notifications", "new_oracle_registration", %{
          "oracle_address" =>
            tx
            |> SignedTx.hash_tx()
            |> OracleRegistrationTxData.bech32_encode(),
          "tx" => Serialization.tx(tx, :serialize)
        })

      %OracleQueryTxData{} ->
        Endpoint.broadcast!("room:notifications", "new_oracle_query", %{
          "body" => Serialization.tx(tx, :serialize)
        })

      %OracleResponseTxData{} ->
        Endpoint.broadcast!("room:notifications", "new_oracle_response", %{
          "body" => Serialization.tx(tx, :serialize)
        })
    end
  end
end
