defmodule Aecore.Contract.Tx.ContractCallTx do
  @moduledoc """
  Aecore structure for Contract Call
  """

  use Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Tx.DataTx
  alias Aecore.Chain.{Identifier, Chainstate}
  alias Aecore.Contract.{Contract, Call, CallStateTree, Dispatch, ContractStateTree}
  alias Aecore.Tx.Transaction

  require Aecore.Contract.ContractConstants, as: Constants

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the ContractCall Transaction"
  @type payload :: %{
          contract: Identifier.t(),
          vm_version: integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary(),
          call_stack: [non_neg_integer()]
        }

  @typedoc "Structure of the ContractCall Transaction type"
  @type t :: %ContractCallTx{
          contract: Identifier.t(),
          vm_version: integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary(),
          call_stack: [non_neg_integer()]
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.calls()

  @doc """
  Definition of the ContractCallTx structure

  # Parameters
  - contract: the address of the contract
  - vm_version: the VM/ABI to use
  - amount: optional amount to transfer to the account before execution (even if the execution fails)
  - gas: the amount of gas to use
  - gas_price: gas price for the call
  - call_data: call data for the call (usually including a function name and args, interpreted by the contract)
  - call_stack: nested calls stack
  """
  defstruct [
    :contract,
    :vm_version,
    :amount,
    :gas,
    :gas_price,
    :call_data,
    :call_stack
  ]

  use ExConstructor

  defguardp is_non_neg_integer(value) when is_integer(value) and value >= 0

  @spec get_chain_state_name() :: :calls
  def get_chain_state_name, do: :calls

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  @spec init(payload()) :: ContractCallTx.t()
  def init(%{
        contract: %Identifier{} = identified_contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }) do
    if Enum.member?([Constants.aevm_sophia_01(), Constants.aevm_solidity_01()], vm_version) do
      %ContractCallTx{
        contract: identified_contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }
    else
      {:error, "#{__MODULE__}: Wrong VM version"}
    end
  end

  def init(%{
        contract: contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }) do
    identified_contract = Identifier.create_identity(contract, :contract)

    if Enum.member?([Constants.aevm_sophia_01(), Constants.aevm_solidity_01()], vm_version) do
      %ContractCallTx{
        contract: identified_contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }
    else
      {:error, "#{__MODULE__}: Wrong VM version"}
    end
  end

  @spec validate(ContractCallTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %ContractCallTx{
          contract: contract
        },
        _data_tx
      ) do
    if Identifier.valid?(contract, :contract) do
      :ok
    else
      {:error, "#{__MODULE__}: Invalid contract address: #{inspect(contract)}"}
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          Chainstate.t(),
          non_neg_integer(),
          ContractCallTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        chain_state,
        block_height,
        %ContractCallTx{
          contract: %Identifier{value: address},
          amount: amount,
          gas_price: gas_price
        } = call_tx,
        %DataTx{
          nonce: nonce,
          senders: [%Identifier{value: sender}]
        },
        context
      ) do
    # Transfer the attached funds to the callee, before the calling of the contract
    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, amount * -1)
      end)
      |> AccountStateTree.update(address, fn acc ->
        Account.apply_transfer!(acc, block_height, amount)
      end)

    updated_chain_state = Map.put(chain_state, :accounts, updated_accounts_state)

    init_call = Call.new(sender, nonce, block_height, address, gas_price)

    {call, update_chain_state1} =
      run_contract(call_tx, init_call, block_height, nonce, updated_chain_state)

    accounts1 = update_chain_state1.accounts

    accounts2 =
      case context do
        :contract ->
          accounts1

        :transaction ->
          gas_cost = call.gas_used * gas_price
          caller1 = AccountStateTree.get(accounts1, sender)

          AccountStateTree.update(accounts1, caller1.id.value, fn acc ->
            Account.apply_transfer!(acc, block_height, gas_cost * -1)
          end)
      end

    # Insert the call into the state tree. This is mainly to remember what the
    # return value was so that the caller can access it easily.
    # Each block starts with an empty calls tree.
    updated_calls_tree = CallStateTree.insert_call(update_chain_state1.calls, call)

    {:ok, {:unused, %{update_chain_state1 | accounts: accounts2, calls: updated_calls_tree}}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          ContractCallTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        chainstate,
        _block_height,
        %ContractCallTx{amount: amount, gas: gas, gas_price: gas_price, call_stack: call_stack} =
          call_tx,
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]},
        context
      )
      when is_non_neg_integer(gas_price) do
    required_amount = fee + gas * gas_price + amount

    checks =
      case context do
        :transaction ->
          [
            fn -> check_validity(call_stack == [], "Non empty call stack") end,
            fn -> check_account_balance(accounts, sender, required_amount) end,
            fn -> check_call(call_tx, chainstate) end
          ]

        :contract ->
          [
            fn -> check_call(call_tx, chainstate) end,
            fn -> check_contract_balance(accounts, sender, amount) end
          ]
      end

    validate_fns(checks)
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ContractCallTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec encode_to_list(ContractCallTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %ContractCallTx{
          contract: contract,
          vm_version: vm_version,
          amount: amount,
          gas: gas,
          gas_price: gas_price,
          call_data: call_data
        },
        %DataTx{
          senders: senders,
          nonce: nonce,
          fee: fee,
          ttl: ttl
        }
      ) do
    [sender] = senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Identifier.encode_to_binary(contract),
      :binary.encode_unsigned(vm_version),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl),
      :binary.encode_unsigned(amount),
      :binary.encode_unsigned(gas),
      :binary.encode_unsigned(gas_price),
      call_data
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        encoded_contract,
        vm_version,
        fee,
        ttl,
        amount,
        gas,
        gas_price,
        call_data
      ]) do
    with {:ok, contract} <- Identifier.decode_from_binary(encoded_contract) do
      payload = %ContractCallTx{
        contract: contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data
      }

      DataTx.init_binary(
        ContractCallTx,
        payload,
        [encoded_sender],
        :binary.decode_unsigned(fee),
        :binary.decode_unsigned(nonce),
        :binary.decode_unsigned(ttl)
      )
    else
      {:error, _} = error -> error
    end
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  defp run_contract(
         %ContractCallTx{
           contract: %Identifier{value: address} = contract_address,
           vm_version: vm_version,
           amount: amount,
           gas: gas,
           gas_price: gas_price,
           call_data: call_data,
           call_stack: call_stack
         },
         %{caller_address: caller_address} = call,
         block_height,
         _nonce,
         chain_state
       ) do
    contracts_tree = chain_state.contracts
    contract = ContractStateTree.get_contract(contracts_tree, address)

    call_definition = %{
      caller: caller_address,
      contract: contract_address,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      amount: amount,
      call_stack: call_stack,
      code: contract.code,
      call: call,
      height: block_height
    }

    Dispatch.run(vm_version, call_definition, chain_state)
  end

  defp check_account_balance(accounts, sender, required_amount) do
    if Account.balance(accounts, sender) - required_amount > 0 do
      :ok
    else
      {:error, "#{__MODULE__}: Negative balance"}
    end
  end

  defp check_contract_balance(accounts, sender, amount) do
    case AccountStateTree.get(accounts, sender) do
      %Account{} ->
        check_validity(
          Account.balance(accounts, sender) >= amount,
          "#{__MODULE__}: Insufficient funds"
        )

      :none ->
        {:error, "#{__MODULE__}: Contract not found"}
    end
  end

  defp check_call(
         %ContractCallTx{contract: %Identifier{value: address}, vm_version: vm_version},
         chain_state
       ) do
    case ContractStateTree.get_contract(chain_state.contracts, address) do
      %Contract{} = contract ->
        case contract.vm_version == vm_version do
          true -> :ok
          false -> {:error, "#{__MODULE__}: Wrong VM version"}
        end

      :none ->
        {:error, "#{__MODULE__}: Contract does not exist"}
    end
  end

  defp check_validity(true, _), do: :ok
  defp check_validity(false, message), do: {:error, message}

  defp validate_fns(checks), do: validate_fns(checks, [])
  defp validate_fns([], _args), do: :ok

  defp validate_fns([fns | tail], args) do
    case apply(fns, args) do
      :ok ->
        validate_fns(tail, args)

      {:error, _message} = error ->
        error
    end
  end
end
