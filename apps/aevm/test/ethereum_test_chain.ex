defmodule EthereumTestChain do
  @moduledoc """
  Aevm chain API implementation for the ethereum vm tests
  """

  use Bitwise

  alias Aecore.Keys

  require Aevm.AevmConst, as: AevmConst

  @behaviour Aevm.ChainApi

  @type chain_state() :: map()

  @spec get_balance(Keys.pubkey(), ChainApi.chain_state()) :: non_neg_integer()
  def get_balance(<<address::256>>, %{pre: chain_state}) do
    account = Map.get(chain_state, address &&& AevmConst.mask160(), %{})

    Map.get(account, :balance, 0)
  end

  def get_store(%{exec: exec, pre: chain_state}) do
    address = Map.get(exec, :address)
    account = Map.get(chain_state, address, %{})

    Map.get(account, :storage, %{})
  end

  def set_store(store, state) do
    Map.put(state, :storage, store)
  end

  def call_contract(_, _, _, _, _, _) do
    {:error, :cant_call_contracts_with_dummy_chain}
  end

end
