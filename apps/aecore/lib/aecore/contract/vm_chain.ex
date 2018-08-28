defmodule Aecore.Contract.VmChain do

  alias Aecore.Contract.ContractStateTree
  alias Aecore.Contract.Contract
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Keys
  alias Aevm.ChainApi

  @behaviour Aevm.ChainApi

  def get_balance(%{pubkey: pubkey, chain_state: chain_state}) do
    account_tree = chain_state.accounts
    AccountStateTree.get(account_tree, pubkey).balance
  end

  def get_store(%{pubkey: pubkey, chain_state: chain_state}) do
    contract_tree = chain_state.contracts
    case ContractStateTree.get_contract(pubkey) do
      %Contract{} = contract ->
        contract.store
      :none ->
        %{}
    end
  end

  def set_store(%{pubkey: pubkey, chain_state: chain_state} = state, store) do
    contract_tree = chain_state.contracts
    contract = ContractStateTree.get_contract(contract_tree, pubkey)

    new_contract = %Contract{contract | store: store}
    updated_contracts_tree = ContractsStateTree.enter_contract(contract_tree, new_contract)

    %{state | chain_state: %{chain_state | contracts: updated_contracts_tree}}
  end

  def spend(receiver, amount, %{pubkey: pubkey, chain_state: chain_state}) do
    account_tree = chain_state.accounts
    nonce = Account.nonce(account_tree, pubkey)
  end

  def call_contract(target, gas, value, call_data, call_stack, %{pubkey: pubkey, chain_state: chain_state} = state) do
    contract_tree = chain_state.contracts
    case ContractStateTree.get_contract(contract_tree, target) do
      %Contract{} = contract ->
        account_tree = chain_state.accounts
        Account.nonce(account_tree, pubkey)
        vm_version = contract.vm_version
    end
  end

end
