defmodule Aecore.Contract.Dispatch do
  @moduledoc """
    Module for running contracts on the right VM
  """

  alias Aecore.Contract.Call
  alias Aecore.Contract.VmChain
  alias Aevm.State, as: State
  alias Aevm.Aevm, as: Aevm
  alias Aecore.Chain.Chainstate

  require Aecore.Contract.ContractConstants, as: Constants

  @pubkey_size_bits 256

  @spec run(integer(), map(), Chainstate.t()) :: Call.t()
  def run(Constants.aevm_sophia_01(), call_definition, chain_state) do
    call_aevm_sophia_01(call_definition, chain_state)
  end

  def run(Constants.aevm_solidity_01(), call_definition, chain_state) do
    call_aevm_solidity_01(call_definition, chain_state)
  end

  def run(_, %{call: call} = _call_definition, _) do
    # Wrong VM; returns unchanged call
    call
  end

  defp call_aevm_sophia_01(
        %{contract: contract, height: height} = call_definition,
        chain_state
      ) do
    env = set_env(contract.value, height, Constants.aevm_sophia_01(), chain_state)

    spec = %{
      env: env,
      exec: %{},
      pre: %{}
    }

    call_init(call_definition, spec)
  end

  defp call_aevm_solidity_01(
        %{contract: contract, height: height} = call_definition,
        chain_state
      ) do
    env = set_env(contract.value, height, Constants.aevm_solidity_01(), chain_state)

    spec = %{
      env: env,
      exec: %{},
      pre: %{}
    }

    call_init(call_definition, spec)
  end

  defp set_env(contract_pubkey, height, vm_version, chain_state) do
    state = VmChain.new_state(contract_pubkey, chain_state)

    %{
      currentCoinbase: <<>>,
      # Get actual difficulty
      currentDifficulty: 0,
      currentGasLimit: 100_000_000_000,
      currentNumber: height,
      currentTimestamp: :os.system_time(:millisecond),
      chain_state: state,
      chain_api: VmChain,
      vm_version: vm_version
    }
  end

  defp call_init(
        %{
          caller: caller,
          contract: contract_pubkey,
          gas: gas,
          gas_price: gas_price,
          call_data: call_data,
          amount: value,
          call_stack: call_stack,
          code: code,
          call: call,
          height: _height
        },
        spec
      ) do
    <<address::size(@pubkey_size_bits)>> = contract_pubkey.value
    <<caller_address::size(@pubkey_size_bits)>> = caller.value

    spec =
      Map.put(spec, :exec, %{
        code: code,
        address: address,
        caller: caller_address,
        data: call_data,
        gas: gas,
        gasPrice: gas_price,
        origin: caller_address,
        value: value,
        call_stack: call_stack
      })

    state = State.init_vm(spec, %{})

    try do
      %{gas: gas_left, out: out, chain_state: chain_state, return_type: return_type} =
        Aevm.loop(state)

      gas_used = gas - gas_left

      updated_call = %{call | gas_used: gas_used, return_type: return_type, return_value: out}

      {updated_call, chain_state.chain_state}
    catch
      _error ->
        updated_call = %{call | gas_used: gas, return_type: :error}

        {updated_call, spec.env.chain_state.chain_state}
    end
  end
end
