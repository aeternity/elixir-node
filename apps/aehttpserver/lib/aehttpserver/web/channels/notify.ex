defmodule Aehttpserver.Web.Notify do

  def broadcast({:new_transaction_in_the_pool_per_account, acc}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications","new_tx:" <> acc, %{"body" => "!!!!!!New transaction in the pool!!!!!!"})
  end

  def broadcast({:new_transaction_in_the_pool_every}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_transaction_in_the_pool", %{"body" => "!!!!!!New transaction in the pool for everyone!!!!!!"})
  end

  def broadcast({:new_mined_transaction, acc}, tx_data) do
    data = %{fee: tx_data.fee, 
             from_acc: Base.encode16(tx_data.from_acc), 
             to_acc: Base.encode16(tx_data.to_acc), 
             value: tx_data.value}
    {:ok, json} = Poison.encode(data)
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_mined_tx:" <> acc, %{"body" => json})
  end

  def broadcast({:new_block_added_to_chain}) do
  	Aehttpserver.Web.Endpoint.broadcast!("room:notifications", "new_block_added_to_chain", %{"body" => "!!!!!!New block added to chain!!!!!!"})
  end
end