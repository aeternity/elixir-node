defmodule ContractCallTx do
  @moduledoc """
  Aecore structure for Contract Call
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Chain.Identifier
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.{Identifier, Chainstate}
  alias Aecore.Contract.{Call, CallStateTree}
  alias Aecore.Tx.DataTx
  alias Aecore.Contract.Dispatch

  @version 1

  @type id :: binary()

  @type payload :: %{
          caller: Identifier.t(),
          contract: Identifier.t(),
          vm_version: integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary(),
          call_stack: [non_neg_integer()]
        }

  @type t :: %ContractCallTx{
          caller: Identifier.t(),
          contract: Identifier.t(),
          vm_version: integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary(),
          call_stack: [non_neg_integer()]
        }

  @type tx_type_state() :: Chainstate.calls()

  defstruct [
    :caller,
    :contract,
    :vm_version,
    :amount,
    :gas,
    :gas_price,
    :call_data,
    :call_stack
  ]

  use ExConstructor

  @spec get_chain_state_name() :: :calls
  def get_chain_state_name, do: :calls

  @spec init(payload()) :: t()
  def init(%{
        caller: %Identifier{} = identified_caller,
        contract: %Identifier{} = identified_contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }) do
    %ContractCallTx{
      caller: identified_caller,
      contract: identified_contract,
      vm_version: vm_version,
      amount: amount,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      call_stack: call_stack
    }
  end

  def init(%{
        caller: caller,
        contract: contract,
        vm_version: vm_version,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data,
        call_stack: call_stack
      }) do
    identified_caller = Identifier.create_identity(caller, :account)
    identified_contract = Identifier.create_identity(contract, :contract)

    %ContractCallTx{
      caller: identified_caller,
      contract: identified_contract,
      vm_version: vm_version,
      amount: amount,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      call_stack: call_stack
    }
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %ContractCallTx{
          caller: caller,
          contract: contract,
          vm_version: vm_version,
          amount: amount,
          gas: gas,
          gas_price: gas_price,
          call_data: call_data,
          call_stack: call_stack
        },
        data_tx
      ) do
    sender = DataTx.senders(data_tx)

    cond do
      !validate_identifier(caller, :account) ->
        {:error, "#{__MODULE__}: Invalid contract address: #{inspect(caller)}"}

      !validate_identifier(contract, :contract) ->
        {:error, "#{__MODULE__}: Invalid contract address: #{inspect(contract)}"}
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
        calls,
        block_height,
        %ContractCallTx{} = call_tx,
        data_tx
      ) do
    # Transfer the attached funds to the callee, before the calling of the contract
    sender = DataTx.main_sender(data_tx)
    nonce = DataTx.nonce(data_tx)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, call_tx.amount)
      end)

    call = Call.new(call_tx.caller, nonce, block_height, call_tx.contract, call_tx.gas_price)

    run_contract(call_tx, call, block_height, nonce)
  end

  # maybe identified caller and contract
  defp run_contract(
         %ContractCallTx{
           caller: caller,
           contract: contract,
           vm_version: vm_version,
           amount: amount,
           gas: gas,
           gas_price: gas_price,
           call_data: call_data,
           call_stack: call_stack
         } = call_tx,
         call,
         block_height,
         nonce
       ) do
    identified_caller = Identifier.create_identity(caller, :account)
    identified_contract = Identifier.create_identity(contract, :contract)

    contracts_tree = Chainstate.contracts()
    contract = ContractStateTree.get_contact(contract.value, contracts_tree)

    call_definition = %{
      caller: identified_caller.value,
      contract: identified_contract.value,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      amount: amount,
      call_stack: call_stack,
      code: contract.code,
      call: call,
      height: block_height
    }

    Dispatch.run(vm_version, call_definition)
  end

  defp validate_identifier(%Identifier{} = id, type) do
    case type do
      :account ->
        Identifier.create_identity(id.value, :account) == id

      :contract ->
        Identifier.create_identity(id.value, :contract) == id
    end
  end
end
