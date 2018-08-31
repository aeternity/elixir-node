defmodule Aecore.Contract.Tx.ContractCreateTx do
  @moduledoc """
  Contains the transaction structure for creating contracts
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Contract.{Contract, CallStateTree, ContractStateTree}

  require ContractConstants

  @type payload :: %{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  @type t :: %ContractCreateTx{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  @type tx_type_state() :: Chainstate.contracts()

  defstruct [
    :code,
    :vm_version,
    :deposit,
    :amount,
    :gas,
    :gas_price,
    :call_data
  ]

  @spec get_chain_state_name() :: :contracts
  def get_chain_state_name, do: :contracts

  @spec init(payload()) :: t()
  def init(%{
        code: code,
        vm_version: vm_version,
        deposit: deposit,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data
      }) do
    %ContractCreateTx{
      code: code,
      vm_version: vm_version,
      deposit: deposit,
      amount: amount,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data
    }
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %ContractCreateTx{},
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    if length(senders) == 1 do
      :ok
    else
      {:error, "#{__MODULE__}: Invalid senders number"}
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        contracts,
        block_height,
        %ContractCreateTx{
          code: code,
          vm_version: vm_version,
          deposit: deposit,
          amount: amount,
          gas: gas,
          gas_price: gas_price,
          call_data: call_data
        } = tx,
        data_tx
      ) do
    owner = DataTx.main_sender(data_tx)
    contract = Contract.new(owner, data_tx.nonce, vm_version, code, deposit)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(owner, fn acc ->
        Account.apply_transfer!(acc, block_height, amount * -1)
      end)
      |> AccountStateTree.update(contract.id, fn acc ->
        Account.apply_transfer!(acc, block_height, amount)
      end)

    updated_contracts_state = ContractStateTree.insert_contract(contracts, contract)

    call = Call.new(owner, data_tx.nonce, block_height, contract.id, gas_price)

    call_definition = %{
      caller: owner,
      contract: contract.id,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      amount: amount,
      call_stack: [],
      code: contract.code,
      call: call,
      height: block_height
    }

    {call_result, updated_state} =
      Dispatch.run(ContractConstants.aevm_solidity_01(), call_definition)

    final_state =
      case call_result.return_type do
        :ok ->
          gas_cost = (gas - gas_left) * gas_price

          accounts_after_gas_spent =
            AccountStateTree.update(updated_accounts_state, owner, fn acc ->
              Account.apply_transfer!(acc, block_height, (gas_cost + deposit) * -1)
            end)

          updated_contract = %{contract | code: call_result.return_value}

          chain_state_with_call = %{
            updated_state
            | calls: CallStateTree.insert_call(updated_state.calls, call),
              accounts: accounts_after_gas_spent,
              contracts:
                ContractStateTree.insert_contract(updated_state.contracts, updated_contract)
          }

        _error ->
          gas_cost = (gas - gas_left) * gas_price

          accounts_after_gas_spent =
            AccountStateTree.update(updated_accounts_state, owner, fn acc ->
              Account.apply_transfer!(acc, block_height, gas_cost * -1)
            end)

          chain_state_with_call = %{
            updated_state
            | calls: CallStateTree.insert_call(updated_state.calls, call),
              accounts: accounts_after_gas_spent
          }
      end

    {:ok, {:unused, final_state}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(accounts, _contracts, block_height, tx, data_tx) do
    sender = DataTx.main_sender(data_tx)
    total_deduction = data_tx.fee + tx.amount + tx.deposit + tx.gas * tx.gas_price

    if AccountStateTree.get(accounts, sender).balance - total_deduction < 0 do
      {:error, "#{__MODULE__}: Negative balance"}
    else
      :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end
end
