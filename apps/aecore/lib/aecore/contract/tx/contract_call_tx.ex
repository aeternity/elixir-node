 defmodule ContractCallTx do
   @moduledoc """
   Aecore structure for Contract Call
   """

   @behaviour Aecore.Tx.Transaction

   alias __MODULE__
   alias Aecore.Account.{Account, AccountStateTree}
   alias Aecore.Tx.DataTx
   alias Aecore.Chain.Worker, as: Chain
   alias Aecore.Chain.{Identifier, Chainstate}
   alias Aecore.Contract.{Call, CallStateTree, Dispatch, ContractStateTree}
   alias Aecore.Tx.Transaction

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

   defguardp is_non_neg_integer(value) when is_integer(value) and value >= 0

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
           contract: contract
           # vm_version: vm_version,
           # amount: amount,
           # gas: gas,
           # gas_price: gas_price,
           # call_data: call_data,
           # call_stack: call_stack
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
           Transaction.context(),
           DataTx.t()
         ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
   def process_chainstate(
         accounts,
         calls,
         block_height,
         %ContractCallTx{} = call_tx,
         context,
         data_tx
       ) do
     # Transfer the attached funds to the callee, before the calling of the contract
     sender = DataTx.main_sender(data_tx)
     nonce = DataTx.nonce(data_tx)

     chain_state = Chain.chain_state()

     updated_accounts_state =
       accounts
       |> AccountStateTree.update(sender, fn acc ->
         Account.apply_transfer!(acc, block_height, call_tx.amount)
       end)

     updated_chain_state = Map.put(chain_state, :accounts, updated_accounts_state)

     init_call = Call.new(call_tx.caller, nonce, block_height, call_tx.contract, call_tx.gas_price)

     {call, update_chain_state1} =
       run_contract(call_tx, init_call, block_height, nonce, updated_chain_state)

     accounts1 = update_chain_state1.account

     accounts2 =
       case context do
         :contract ->
           accounts1

         :transaction ->
           gas_cost = call.gas_used * call_tx.gas_price
           amount = call_tx.fee + gas_cost
           caller1 = AccountStateTree.get(accounts1, sender)

           accounts1
           |> AccountStateTree.update(caller1, fn acc ->
             Account.apply_transfer!(acc, block_height, amount)
           end)
       end

     # Insert the call into the state tree. This is mainly to remember what the
     # return value was so that the caller can access it easily.
     # Each block starts with an empty calls tree.
     updated_calls_tree =
       calls
       |> CallStateTree.insert_call(calls, call)

     {:ok, {accounts2, updated_calls_tree}}
   end

   @spec preprocess_check(
           Chainstate.accounts(),
           tx_type_state(),
           non_neg_integer(),
           ContractCallTx.t(),
           Transaction.context(),
           DataTx.t()
         ) :: :ok | {:error, String.t()}
   def preprocess_check(
         accounts,
         calls,
         _block_height,
         %ContractCallTx{amount: amount, gas: gas, gas_price: gas_price} = call_tx,
         context,
         data_tx
       )
       when is_non_neg_integer(gas_price) do
     sender = DataTx.main_sender(data_tx)
     fee = DataTx.fee(data_tx)

     chain_state = Chain.chain_state()

     required_amount = fee + gas * gas_price + amount

     checks =
       case context do
         :transaction ->
           [
             fn -> check_validity(call_tx.call_stack == [], "Non empty call stack") end,
             fn -> check_account_balance(accounts, sender, required_amount) end,
             fn -> check_call(call_tx, chain_state) end
           ]

         :contract ->
           [
             fn -> check_call(call_tx, chain_state) end,
             fn -> check_contract_balance(accounts, sender, amount) end
           ]
       end

     case validate_fns(checks) do
       :ok -> :ok
       {:error, message} -> {:error, message}
     end
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
          },
          call,
          block_height,
          _nonce,
          chain_state
        ) do
     identified_caller = Identifier.create_identity(caller, :account)
     identified_contract = Identifier.create_identity(contract, :contract)

     contracts_tree = chain_state.contracts
     # check the get_contract
     contract = ContractStateTree.get_contact(contracts_tree, identified_contract.value)

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

   defp check_account_balance(accounts, sender, required_amount) do
     case AccountStateTree.get(accounts, sender).balance - required_amount > 0 do
       true -> :ok
       false -> {:error, "#{__MODULE__}: Negative balance"}
     end
   end

   defp check_contract_balance(accounts, sender, amount) do
     case AccountStateTree.get(accounts, sender) do
       account ->
         check_validity(
           Account.balance(accounts, sender) >= amount,
           "#{__MODULE__}: Insufficient funds"
         )

       :none ->
         {:error, "#{__MODULE__}: Contract not found"}
     end
   end

   defp check_call(
          %ContractCallTx{contract: contract, vm_version: vm_version, amount: amount},
          chain_state
        ) do
     case ContractStateTree.get(chain_state.contracts, contract.value) do
       {:ok, contract} ->
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

   defp validate_identifier(%Identifier{} = id, type) do
     case type do
       :account ->
         Identifier.create_identity(id.value, :account) == id

       :contract ->
         Identifier.create_identity(id.value, :contract) == id
     end
   end

   defp validate_fns(checks), do: validate_fns(checks, [])
   defp validate_fns([], _args), do: :ok
   defp validate_fns([fns, tail], args) do
     case apply(fns, args) do
       :ok ->
         validate_fns(tail, args)

       {:error, _message} = error ->
         error
     end
   end
 end
