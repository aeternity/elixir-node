defmodule Aecore.Contract.VmChain do
  @moduledoc """
  VM chain api implementation for interaction with our chain
  """

  alias Aecore.Account.Account
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Contract.{ContractStateTree, CallStateTree, Contract, Call}
  alias Aecore.Keys
  alias Aecore.Tx.DataTx
  alias Aevm.ChainApi

  @behaviour Aevm.ChainApi

  @spec new_state(Keys.pubkey(), Chainstate.t()) :: ChainApi.chain_state()
  def new_state(pubkey, chain_state) do
    %{pubkey: pubkey, chain_state: chain_state}
  end

  @spec get_balance(Keys.pubkey(), ChainApi.chain_state()) :: non_neg_integer()
  def get_balance(pubkey, %{accounts: account_tree}) do
    Account.balance(account_tree, pubkey)
  end

  @spec get_store(ChainApi.chain_state()) :: ChainApi.store()
  def get_store(%{pubkey: pubkey, chain_state: %{contracts: contract_tree}}) do
    case ContractStateTree.get_contract(contract_tree, pubkey) do
      %Contract{store: store} ->
        store

      :none ->
        %{}
    end
  end

  @spec set_store(ChainApi.store(), ChainApi.chain_state()) :: ChainApi.chain_state()
  def set_store(
        store,
        %{pubkey: pubkey, chain_state: %{contracts: contract_tree} = chain_state} = state
      ) do
    contract = ContractStateTree.get_contract(contract_tree, pubkey)

    new_contract = %Contract{contract | store: store}
    updated_contracts_tree = ContractStateTree.enter_contract(contract_tree, new_contract)

    %{state | chain_state: %{chain_state | contracts: updated_contracts_tree}}
  end

  @spec call_contract(
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          [non_neg_integer()],
          ChainApi.chain_state()
        ) :: {:ok, ChainApi.call_result(), ChainApi.chain_state()} | {:error, String.t()}
  def call_contract(target, gas, value, call_data, call_stack, %{
        pubkey: contract_key,
        chain_state: chain_state
      }) do
    contract_tree = chain_state.contracts

    case ContractStateTree.get_contract(contract_tree, target) do
      %Contract{} = contract ->
        account_tree = chain_state.accounts
        nonce = Account.nonce(account_tree, contract_key) + 1
        vm_version = contract.vm_version

        payload = %{
          caller: contract_key,
          contract: target,
          vm_version: vm_version,
          amount: value,
          gas: gas,
          gas_price: 0,
          call_data: call_data,
          call_stack: call_stack
        }

        height = Chain.top_height() + 1
        tx = DataTx.init(ContractCallTx, payload, contract_key, 0, nonce)
        do_call_contract(chain_state, height, tx)

      :none ->
        {:error, "#{__MODULE__}: No such contract: #{inspect(target)}"}
    end
  end

  defp do_call_contract(
         chain_state,
         height,
         %DataTx{
           nonce: nonce,
           payload: %{caller: contract_key, contract: target}
         } = tx
       ) do
    with :ok <- DataTx.preprocess_check(chain_state, height, tx),
         {:ok, new_chain_state} <- DataTx.process_chainstate(chain_state, height, tx) do
      call_id = Call.id(contract_key, nonce, target)
      call_tree_key = CallStateTree.construct_call_tree_id(contract_key, call_id)
      call = CallStateTree.get_call(new_chain_state.calls, call_tree_key)
      gas_used = call.gas_used

      result =
        case call.return_type do
          return_type when return_type in [:ok, :revert] ->
            %{result: call.return_value, gas_spent: gas_used}

          :error ->
            %{result: :error, gas_spent: gas_used}
        end

      {:ok, result, new_chain_state}
    else
      error ->
        error
    end
  end
end
