defmodule Aecore.Contract.Tx.ContractCreateTx do
  @moduledoc """
  Contains the transaction structure for creating contracts
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account
  alias Aecore.Contract.{Contract, Call, CallStateTree, ContractStateTree, Dispatch}
  alias Aecore.Tx.Transaction
  alias Aecore.Tx.DataTx
  alias Aecore.Chain.Identifier

  require Aecore.Contract.ContractConstants, as: Constants

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the ContractCreate Transaction"
  @type payload :: %{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  @typedoc "Structure of the ContractCreate Transaction type"
  @type t :: %ContractCreateTx{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.contracts()

  @doc """
  Definition of the ContractCreateTx structure

  # Parameters
  - code: the byte code of the contract
  - vm_version: the VM/ABI to use
  - deposit: held by the contract until it is deactivated (an even number, 0 is accepted)
  - amount: to be added to the miner account
  - gas: gas for the initial call
  - gas_price: gas price for the call
  - call_data: call data for the initial call (usually including a function name and args, interpreted by the contract)
  """
  defstruct [
    :code,
    :vm_version,
    :deposit,
    :amount,
    :gas,
    :gas_price,
    :call_data
  ]

  use ExConstructor

  @spec get_chain_state_name() :: :contracts
  def get_chain_state_name, do: :contracts

  @spec init(payload()) :: t() | {:error, reason()}
  def init(%{
        code: code,
        vm_version: vm_version,
        deposit: deposit,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data
      }) do
    if Enum.member?([Constants.aevm_sophia_01(), Constants.aevm_solidity_01()], vm_version) do
      %ContractCreateTx{
        code: code,
        vm_version: vm_version,
        deposit: deposit,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data
      }
    else
      {:error, "#{__MODULE__}: Wrong VM version"}
    end
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ContractCreateTx{},
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    if length(senders) == 1 do
      :ok
    else
      {:error, "#{__MODULE__}: Wrong senders number"}
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          Chainstate.t(),
          non_neg_integer(),
          t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        chain_state,
        block_height,
        %ContractCreateTx{
          code: code,
          vm_version: vm_version,
          deposit: deposit,
          amount: amount,
          gas: gas,
          gas_price: gas_price,
          call_data: call_data
        },
        data_tx,
        _context
      ) do
    owner = DataTx.main_sender(data_tx)
    contract = Contract.new(owner, data_tx.nonce, vm_version, code, deposit)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(owner, fn acc ->
        Account.apply_transfer!(acc, block_height, amount * -1)
      end)
      |> AccountStateTree.update(contract.id.value, fn acc ->
        Account.apply_transfer!(acc, block_height, amount)
      end)

    updated_contracts_state = ContractStateTree.insert_contract(chain_state.contracts, contract)

    call = Call.new(owner, data_tx.nonce, block_height, contract.id.value, gas_price)

    call_definition = %{
      caller: call.caller_address,
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

    pre_call_chain_state = %{
      chain_state
      | contracts: updated_contracts_state,
        accounts: updated_accounts_state
    }

    {call_result, updated_state} =
      Dispatch.run(Constants.aevm_solidity_01(), call_definition, pre_call_chain_state)

    final_state =
      case call_result.return_type do
        return_type when return_type in [:ok, :revert] ->
          gas_cost = call_result.gas_used * gas_price

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
                ContractStateTree.enter_contract(updated_state.contracts, updated_contract)
          }

        _error ->
          gas_cost = call_result.gas_used * gas_price

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
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(accounts, _contracts, _block_height, tx, data_tx, _context) do
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

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(ContractCreateTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ContractCreateTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      tx.code,
      :binary.encode_unsigned(tx.vm_version),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(tx.deposit),
      :binary.encode_unsigned(tx.amount),
      :binary.encode_unsigned(tx.gas),
      :binary.encode_unsigned(tx.gas_price),
      tx.call_data
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        code,
        vm_version,
        fee,
        ttl,
        deposit,
        amount,
        gas,
        gas_price,
        call_data
      ]) do
    payload = %{
      code: code,
      vm_version: :binary.decode_unsigned(vm_version),
      deposit: :binary.decode_unsigned(deposit),
      amount: :binary.decode_unsigned(amount),
      gas: :binary.decode_unsigned(gas),
      gas_price: :binary.decode_unsigned(gas_price),
      call_data: call_data
    }

    DataTx.init_binary(
      ContractCreateTx,
      payload,
      [encoded_sender],
      :binary.decode_unsigned(fee),
      :binary.decode_unsigned(nonce),
      :binary.decode_unsigned(ttl)
    )
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
