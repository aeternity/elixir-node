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

  def call_aevm_sophia_01(%{contract: contract, height: height} = call_definition) do
    env = set_env(contract.value, height, Constants.aevm_sophia_01())

    spec = %{
      env: env,
      exec: %{},
      pre: %{}
    }

    call_init(call_definition, spec)
  end

  def call_aevm_solidity_01(%{contract: contract, height: height} = call_definition) do
    env = set_env(contract.value, height, Constants.aevm_solidity_01())

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
      chainState: Chain.chain_state(),
      chainApi: VmChain,
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

    # will be removed
    opts = %{}
    call_depth = 0
    # to be changed
    # error checking
    state = State.init_vm(spec, call_depth, opts)
    # error checking for:
    # :ok - setting gas_used and return_type in call
    # :revert - setting gas_used and return_type in call
    # :error - Execution resulting in VM exeception;
    # Gas used, but other state not affected.
    try do
      init_state = Aevm.init(state)
      case Aevm.loop(init_state) do
        {:ok, %{gas_left: gas_left, out: out, chain_state: chain_state}} ->
          gas_used = gas - gas_left
          {gas_used, chain_state}
        {}
      end
    catch
      error -> {:error, "#{__MODULE__}: call_init: #{error}"}
    end
  end
end
