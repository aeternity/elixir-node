defmodule Dispatch do
  @moduledoc """
    Module for running contracts on the right VM
  """

  alias Aecore.Contract.Call
  alias Aecore.Contract.VmChain
  alias Aevm.State, as: State
  alias Aevm.Aevm, as: Aevm
  alias Aecore.Chain.Worker, as: Chain

  require ContractConstants, as: Constants

  @pubkey_size_bits 256

  @spec run(integer(), map()) :: Call.t()
  def run(Constants.aevm_sophia_01(), call_definition) do
    call_aevm_sophia_01(call_definition)
  end

  def run(Constants.aevm_solidity_01(), call_definition) do
    call_aevm_solidity_01(call_definition)
  end

  def run(_, %{call: call} = _call_definition) do
    # Wrong VM; returns unchanged call
    call
  end

  def call_aevm_sophia_01(%{contract_address: contract_address, height: height} = call_definition) do
    env = set_env(contract_address.value, height, Constants.aevm_sophia_01())

    spec = %{
      env: env,
      exec: %{},
      pre: %{}
    }

    call_init(call_definition, spec)
  end

  def call_aevm_solidity_01(
        %{contract_address: contract_address, height: height} = call_definition
      ) do
    env = set_env(contract_address.value, height, Constants.aevm_solidity_01())

    spec = %{
      env: env,
      exec: %{},
      pre: %{}
    }

    call_init(call_definition, spec)
  end

  def set_env(contract_pubkey, height, vm_version) do
    chainstate = %{pubkey: contract_pubkey, chain_state: Chain.chain_state()}

    %{
      currentCoinbase: <<>>,
      # Get actual difficulty
      currentDifficulty: 0,
      currentGasLimit: 100_000_000_000,
      currentNumber: height,
      currentTimestamp: :os.system_time(:millisecond),
      chain_state: Chain.chain_state(),
      chain_api: VmChain,
      vm_version: vm_version
    }
  end

  def call_init(
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
    <<address::size(@pubkey_size_bits)>> = contract_pubkey
    <<caller_address::size(@pubkey_size_bits)>> = caller

    Map.put(spec, :exec, %{
      code: code,
      address: address,
      data: call_data,
      gas: gas,
      gas_price: gas_price,
      origin: caller_address,
      value: value,
      call_stack: call_stack
    })

    state = State.init_vm(spec, call_depth, opts)

    try do
      init_state = Aevm.init(state)

      {return_type, %{gas_left: gas_left, out: out, chain_state: chain_state}} =
        Aevm.loop(init_state)

      gas_used = gas - gas_left

      updated_call =
        call
        |> Call.set_gas_used(gas_used)
        |> Call.set_return_type(return_type)
        |> Call.set_return_value(out)

      {updated_call, chain_state}
    catch
      _error ->
        updated_call = call |> Call.set_gas_used(gas) |> Call.set_return_type(:error)

        {updated_call, spec.env.chainState}
    end
  end
end
