 defmodule Aecore.Contract.Tx.ContractCallTx do
   @moduledoc """
   Aecore structure for Contract Call
   """

   @behaviour Aecore.Tx.Transaction

   alias __MODULE__
   alias Aecore.Account.{Account, AccountStateTree}
   alias Aecore.Tx.DataTx
   alias Aecore.Chain.Worker, as: Chain
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

   @spec init(payload()) :: t()
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

   @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
   def validate(
         %ContractCallTx{
           contract: contract
         },
         _data_tx
       ) do
     if Identifier.check_identity(contract, :contract) do
       :ok
     else
       {:error, "#{__MODULE__}: Invalid contract address: #{inspect(contract)}"}
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
         %ContractCallTx{} = call_tx,
         data_tx,
         context
       ) do
     # Transfer the attached funds to the callee, before the calling of the contract
     sender = DataTx.main_sender(data_tx)
     nonce = DataTx.nonce(data_tx)

     updated_accounts_state =
       AccountStateTree.update(accounts, sender, fn acc ->
         Account.apply_transfer!(acc, block_height, call_tx.amount)
       end)

     updated_chain_state = Map.put(chain_state, :accounts, updated_accounts_state)

     init_call = Call.new(sender, nonce, block_height, call_tx.contract.value, call_tx.gas_price)

     {call, update_chain_state1} =
       run_contract(call_tx, init_call, block_height, nonce, updated_chain_state)

     accounts1 = update_chain_state1.accounts

     accounts2 =
       case context do
         :contract ->
           accounts1

         :transaction ->
           gas_cost = call.gas_used * call_tx.gas_price
           amount = DataTx.fee(data_tx) + gas_cost
           caller1 = AccountStateTree.get(accounts1, sender)

           AccountStateTree.update(accounts1, caller1.id.value, fn acc ->
             Account.apply_transfer!(acc, block_height, amount)
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
         _calls,
         _block_height,
         %ContractCallTx{amount: amount, gas: gas, gas_price: gas_price} = call_tx,
         data_tx,
         context
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
   def encode_to_list(%ContractCallTx{} = tx, %DataTx{} = datatx) do
     [sender] = datatx.senders

     [
       :binary.encode_unsigned(@version),
       Identifier.encode_to_binary(sender),
       :binary.encode_unsigned(datatx.nonce),
       Identifier.encode_to_binary(tx.contract),
       :binary.encode_unsigned(tx.vm_version),
       :binary.encode_unsigned(datatx.fee),
       :binary.encode_unsigned(datatx.ttl),
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

   @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
   def is_minimum_fee_met?(tx) do
     tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
   end

   defp run_contract(
          %ContractCallTx{
            contract: contract_address,
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
     contract = ContractStateTree.get_contract(contracts_tree, contract_address.value)

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
          %ContractCallTx{contract: contract, vm_version: vm_version},
          chain_state
        ) do
     case ContractStateTree.get_contract(chain_state.contracts, contract.value) do
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
