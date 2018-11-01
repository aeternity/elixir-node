defmodule Aevm.State do
  @moduledoc """
  Module for handling and accessing values from the VM's internal state.
  """

  alias Aevm.AevmUtil

  @doc """
  Initialize the VM's internal state.

  `exec`      - transaction information
  `env`       - environmental Information
  `pre`       - previous world state (mapping between addresses and accounts)
  `opts`      - VM options
  """
  @spec init_vm(map(), map()) :: map()
  def init_vm(
        %{
          exec:
            %{
              code: code,
              address: address,
              origin: origin,
              caller: caller,
              data: data,
              gasPrice: gas_price,
              gas: gas,
              value: value
            } = exec,
          env: %{
            chain_api: chain_api,
            chain_state: chain_state,
            currentCoinbase: current_coinbase,
            currentDifficulty: current_difficulty,
            currentGasLimit: current_gas_limit,
            currentNumber: current_number,
            currentTimestamp: current_timestamp,
            vm_version: vm_version
          },
          pre: pre
        },
        opts
      ) do
    %{
      :stack => [],
      :memory => %{size: 0},
      :storage => chain_api.get_store(chain_state),
      :pc => 0,
      :jumpdests => [],
      :out => <<>>,
      :logs => [],
      :callcreates => [],
      # exec
      :address => address,
      :origin => origin,
      :caller => caller,
      :data => data,
      :code => code,
      :gasPrice => gas_price,
      :gas => gas,
      :value => value,
      :return_data => Map.get(exec, :return_data, <<>>),
      :call_stack => Map.get(exec, :call_stack, []),
      # env
      :currentCoinbase => current_coinbase,
      :currentDifficulty => current_difficulty,
      :currentGasLimit => current_gas_limit,
      :currentNumber => current_number,
      :currentTimestamp => current_timestamp,
      # pre
      :pre => pre,
      # chain
      :vm_version => vm_version,
      :chain_api => chain_api,
      :chain_state => chain_state,
      :return_type => :ok,
      # opts
      :execute_calls => Map.get(opts, :execute_calls, false)
    }
  end

  @doc """
  Initialize a state for CALL instruction
  """
  @spec init_for_call(
          integer(),
          integer(),
          integer(),
          binary(),
          integer(),
          integer(),
          map(),
          map()
        ) :: map()
  def init_for_call(gas, to, value, data, caller, dest, caller_state, opts) do
    exec = export_exec(gas, to, value, data, caller, dest, caller_state)
    env = export_env(caller_state)
    pre = Map.get(caller_state, :pre, %{})

    init_vm(%{exec: exec, env: env, pre: pre}, opts)
  end

  def call_contract(
        caller,
        target,
        gas,
        value,
        data,
        %{call_stack: call_stack, chain_api: chain_api, chain_state: chain_state} = state
      ) do
    new_call_stack = [caller | call_stack]
    target_key = <<target::size(256)>>

    case chain_api.call_contract(target_key, gas, value, data, new_call_stack, chain_state) do
      {:ok, %{gas_spent: gas_spent, result: result}, chain_state_after_call} ->
        {:ok, result, gas_spent, set_chain_state(state, chain_state_after_call)}

      {:error, message} ->
        {:error, message}
    end
  end

  def save_storage(%{chain_api: chain_api, chain_state: chain_state, storage: storage} = state) do
    binary_storage = storage_to_bin(storage)

    %{state | chain_state: chain_api.set_store(binary_storage, chain_state)}
  end

  def storage_to_bin(storage) do
    Enum.reduce(storage, %{}, fn {key, value}, acc ->
      Map.put(acc, :binary.encode_unsigned(key), :binary.encode_unsigned(value))
    end)
  end

  def storage_to_int(storage) do
    Enum.reduce(storage, %{}, fn {key, value}, acc ->
      <<key_int::256>> = key
      <<value_int::256>> = value

      Map.put(acc, key_int, value_int)
    end)
  end

  def calldepth(%{call_stack: call_stack}) do
    call_stack |> Enum.count()
  end

  def execute_calls(state) do
    Map.get(state, :execute_calls, false)
  end

  def add_callcreate(data, destination, gas_limit, value, state) do
    callcreates = Map.get(state, :callcreates)

    Map.put(state, :callcreates, [
      %{
        :data => data,
        :destination => destination,
        :gasLimit => gas_limit,
        :value => value
      }
      | callcreates
    ])
  end

  def set_stack(stack, state) do
    Map.put(state, :stack, stack)
  end

  def set_memory(memory, state) do
    Map.put(state, :memory, memory)
  end

  def set_storage(storage, state) do
    Map.put(state, :storage, storage)
  end

  def set_pc(pc, state) do
    Map.put(state, :pc, pc)
  end

  def set_out(out, state) do
    Map.put(state, :out, out)
  end

  def set_logs(logs, state) do
    Map.put(state, :logs, logs)
  end

  def set_gas(gas, state) do
    Map.put(state, :gas, gas)
  end

  def set_selfdestruct(value, state) do
    Map.put_new(state, :selfdestruct, value)
  end

  def set_chain_state(chain_state, state) do
    Map.put(state, :chain_state, chain_state)
  end

  def set_return_type(return_type, state) do
    Map.put(state, :return_type, return_type)
  end

  def get_balance(address, %{chain_api: chain_api, chain_state: chain_state}) do
    pubkey = <<address::size(256)>>
    chain_api.get_balance(pubkey, chain_state)
  end

  def get_ext_code_size(address, %{pre: pre}) do
    account = Map.get(pre, address, %{})
    code = Map.get(account, :code, <<>>)

    byte_size(code)
  end

  def get_code(address, state) do
    pre = Map.get(state, :pre)
    account = Map.get(pre, address, %{})

    Map.get(account, :code, <<>>)
  end

  def inc_pc(state) do
    pc = Map.get(state, :pc)
    Map.put(state, :pc, pc + 1)
  end

  def calculate_blockhash(nth_block, a, %{currentNumber: current_number}) do
    # Because the data of the blockchain is not
    # given, the opcode BLOCKHASH could not
    # return the hashes of the corresponding
    # blocks. Therefore we define the hash of
    # block number n to be SHA3-256("n").
    cond do
      nth_block >= current_number ->
        0

      a == 256 ->
        0

      # h == 0 -> 0

      current_number - 256 > nth_block ->
        0

      true ->
        bin_nth_block = <<nth_block::256>>
        hash = AevmUtil.sha3_hash(bin_nth_block)
        <<value::integer-unsigned-256>> = hash
        value
    end
  end

  @doc """
  Convert given `bytecode` to binary
  """
  def bytecode_to_bin(bytecode) do
    bytecode
    |> String.replace("0x", "")
    |> String.to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn x, acc ->
      {code, _} = x |> List.to_string() |> Integer.parse(16)

      [code | acc]
    end)
    |> Enum.reverse()
    |> Enum.reduce(<<>>, fn x, acc ->
      acc <> <<x::size(8)>>
    end)
  end

  defp export_exec(
         gas,
         to,
         value,
         data,
         caller,
         dest,
         %{origin: origin, gasPrice: gas_price, call_stack: call_stack} = state
       ) do
    %{
      :address => dest,
      :origin => origin,
      :caller => caller,
      :data => data,
      :code => state |> Map.get(:pre, %{to => %{:code => <<>>}}) |> Map.get(to) |> Map.get(:code),
      :gasPrice => gas_price,
      :gas => gas,
      :value => value,
      :call_stack => [caller | call_stack]
    }
  end

  defp export_env(%{
         currentCoinbase: current_coinbase,
         currentDifficulty: current_difficulty,
         currentGasLimit: current_gas_limit,
         currentNumber: current_number,
         currentTimestamp: current_timestamp,
         chain_api: chain_api,
         chain_state: chain_state,
         vm_version: vm_version
       }) do
    %{
      :currentCoinbase => current_coinbase,
      :currentDifficulty => current_difficulty,
      :currentGasLimit => current_gas_limit,
      :currentNumber => current_number,
      :currentTimestamp => current_timestamp,
      :chain_api => chain_api,
      :chain_state => chain_state,
      :vm_version => vm_version
    }
  end
end
