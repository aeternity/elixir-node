defmodule Aehttpserver.Web.Notify do
  alias Aeutil.Serialization

  def broadcast_new_transaction_in_the_pool(tx) do
    from_acc = Base.encode16(tx.data.from_acc)
    to_acc = Base.encode16(tx.data.to_acc)
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications","new_tx:" <> from_acc, %{"body" => Serialization.tx(tx, :serialize)})
    Aehttpserver.Web.Endpoint.broadcast!("room:notifications","new_tx:" <> to_acc, %{"body" => Serialization.tx(tx, :serialize)})
    Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_transaction_in_the_pool", %{"body" => Serialization.tx(tx, :serialize)})
  end

  def broadcast_new_mined_transaction(tx) do
    from_acc = Base.encode16(tx.data.from_acc)
    to_acc = Base.encode16(tx.data.to_acc)
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_mined_tx:" <> from_acc, %{"body" => Serialization.tx(tx, :serialize)})
    Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_mined_tx:" <> to_acc, %{"body" => Serialization.tx(tx, :serialize)})
  end

  def broadcast_new_block_added_to_chain(block) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{"body" => Serialization.block(block, :serialize)})
  end
end