defmodule Aecore.Channel.Updates.ChannelCreateContractUpdate do
  @moduledoc """
  State channel update for creating new contracts inside channel's off-chain state tree. This update can be included in ChannelOffchainTx.
  """

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Channel.Updates.ChannelCreateContractUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Contract.ContractConstants, as: Constants
  alias Aecore.Chain.Identifier

  @behaviour ChannelOffChainUpdate

  @typedoc """
  Structure of the ChannelDepositUpdate type
  """
  @type t :: %ChannelCreateContractUpdate{
          owner: binary(),
          vm_version: Constants.aevm_sophia_01() | Constants.aevm_solidity_01(),
          code: binary(),
          deposit: non_neg_integer(),
          call_data: binary()
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of ChannelCreateContract structure

  ## Parameters
  - owner: the owner of the contract
  - vm_version: version of the vm on which the code will be run
  - code: the bytecode for the virtual machine
  - deposit: the initial deposit made by the owner of the contract
  - call_data: data for the initial call
  """
  defstruct [:owner, :vm_version, :code, :deposit, :call_data]


  @doc """
  Deserializes ChannelCreateContractUpdate
  """
  @spec decode_from_list(list(binary())) :: ChannelCreateContractUpdate.t() | error()
  def decode_from_list([encoded_owner, encoded_vm_version, code, deposit, call_data]) do
    with {:ok, owner} <- Identifier.decode_from_binary_to_value(encoded_owner, :account),
         vm_version <- :binary.decode_unsigned(encoded_vm_version),
         true <- vm_version in [Contants.aevm_sophia_01(), Contants.aevm_solidity_01] do
        %ChannelCreateContractUpdate {
          owner: owner,
          vm_version: vm_version,
          code: code,
          deposit: :binary.decode_unsigned(deposit),
          call_data: call_data
        }
      else
        {:error, _} = err ->
          err
        false ->
          {:error, "#{__MODULE__}: Invalid vm version, got: #{vm_version}"}
    end
  end

  @doc """
  Serializes ChannelCreateContractUpdate.
  """
  @spec encode_to_list(ChannelCreateContractUpdate.t()) :: list(binary())
  def encode_to_list(%ChannelCreateContractUpdate{
        owner: owner,
        vm_version: vm_version,
        code: code,
        deposit: deposit,
        call_data: call_data
      }) do
    [
      Identifier.create_encoded_to_binary(owner, :account),
      :binary.encode_unsigned(vm_version),
      code,
      :binary.encode_unsigned(deposit),
      call_data
    ]
  end

  @doc """
  Creates a contract in the offchain chainstate.
  """
  @spec update_offchain_chainstate!(Chainstate.t(), ChannelCreateContractUpdate.t()) ::
          Chainstate.t() | no_return()
  def update_offchain_chainstate!(
        %Chainstate{
          accounts: accounts,
          contracts: contracts,
          calls: calls
        } = chainstate,
        %ChannelCreateContractUpdate{
          owner: owner,
          vm_version: vm_version,
          code: code,
          deposit: deposit,
          call_data: call_data
        }
      ) do



"""
    contract = Contract.new(owner, nonce, vm_version, code, deposit)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(owner, fn acc ->
        Account.apply_transfer!(acc, block_height, amount * -1)
      end)
      |> AccountStateTree.update(contract.id.value, fn acc ->
        Account.apply_transfer!(acc, block_height, amount)
      end)

    updated_contracts_state = ContractStateTree.insert_contract(chain_state.contracts, contract)

    call = Call.new(owner, nonce, block_height, contract.id.value, gas_price)

    call_definition = %{
      caller: call.caller_address,
      contract: contract.id,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      # Initial call takes no amount
      amount: 0,
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

          updated_store = ContractStateTree.get(updated_state.contracts, contract.id.value).store
          updated_contract = %{contract | code: call_result.return_value, store: updated_store}

          chain_state_with_call = %{
            updated_state
            | calls: CallStateTree.insert_call(updated_state.calls, call_result),
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
"""




    %Chainstate{chainstate | accounts: updated_accounts}
  end
