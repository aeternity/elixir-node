defmodule Aehttpserver.Web.Notify do

  def broadcast({:new_transaction_in_the_pool_per_account, acc}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications","new_tx:" <> acc, %{"body" => "!!!!!!New transaction in the pool!!!!!!"})
  end

  def broadcast({:new_transaction_in_the_pool_every}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_transaction_in_the_pool", %{"body" => "!!!!!!New transaction in the pool for everyone!!!!!!"})
  end

  def broadcast({:new_mined_transaction, acc}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_mined_tx:" <> acc, %{"body" => "!!!!!!New mined transaction!!!!!!"})
  end

  def broadcast({:new_block_added_to_chain}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{"body" => "!!!!!!New block added to chain!!!!!!"})
  end
end