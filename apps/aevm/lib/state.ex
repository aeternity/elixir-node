defmodule State do
  @moduledoc """
    Module for handling state
  """

  @spec init_vm(map(), map(), map(), integer(), map()) :: map()
  def init_vm(exec, env, pre, calldepth, opts) do
    bytecode = Map.get(exec, :code)

    %{
      :stack => [],
      :memory => %{size: 0},
      :storage => init_storage(Map.get(exec, :address), pre),
      :cp => 0,
      :jumpdests => [],
      :out => <<>>,
      :logs => [],
      :callcreates => [],

      :address => Map.get(exec, :address),
      :origin => Map.get(exec, :origin),
      :caller => Map.get(exec, :caller),
      :data => Map.get(exec, :data),
      :code => bytecode,
      :gasPrice => Map.get(exec, :gasPrice),
      :gas => Map.get(exec, :gas),
      :value => Map.get(exec, :value),
      :return_data => Map.get(exec, :return_data, <<>>),

      :currentCoinbase => Map.get(env, :currentCoinbase),
      :currentDifficulty => Map.get(env, :currentDifficulty),
      :currentGasLimit => Map.get(env, :currentGasLimit),
      :currentNumber => Map.get(env, :currentNumber),
      :currentTimestamp => Map.get(env, :currentTimestamp),

      :pre => pre,

      :calldepth => calldepth,

      # opts
      :execute_calls => Map.get(opts, :execute_calls, false)
    }
  end

  def init_for_call(gas, to, value, data, caller, dest, caller_state, opts) do
    exec = export_exec(gas, to, value, data, caller, dest, caller_state)
    env = export_env(caller_state)
    pre = Map.get(caller_state, :pre, %{})
    calldepth = State.calldepth(caller_state) + 1

    init_vm(exec, env, pre, calldepth, opts)
  end

  def calldepth(state) do
    Map.get(state, :calldepth)
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

  def set_cp(cp, state) do
    Map.put(state, :cp, cp)
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

  def stack(state) do
    Map.get(state, :stack)
  end

  def memory(state) do
    Map.get(state, :memory)
  end

  def storage(state) do
    Map.get(state, :storage)
  end

  def code(state) do
    Map.get(state, :code)
  end

  def cp(state) do
    Map.get(state, :cp)
  end

  def jumpdests(state) do
    Map.get(state, :jumpdests)
  end

  def logs(state) do
    Map.get(state, :logs)
  end

  def address(state) do
    Map.get(state, :address)
  end

  def caller(state) do
    Map.get(state, :caller)
  end

  def data(state) do
    Map.get(state, :data)
  end

  def gas(state) do
    Map.get(state, :gas)
  end

  def gas_price(state) do
    Map.get(state, :gasPrice)
  end

  def origin(state) do
    Map.get(state, :origin)
  end

  def value(state) do
    Map.get(state, :value)
  end

  def current_coinbase(state) do
    Map.get(state, :currentCoinbase)
  end

  def current_difficulty(state) do
    Map.get(state, :currentDifficulty)
  end

  def current_gas_limit(state) do
    Map.get(state, :currentGasLimit)
  end

  def current_number(state) do
    Map.get(state, :currentNumber)
  end

  def current_timestamp(state) do
    Map.get(state, :currentTimestamp)
  end

  def get_balance(address, state) do
    pre = Map.get(state, :pre)
    account = Map.get(pre, address, %{})
    Map.get(account, :balance, 0)
  end

  def get_ext_code_size(address, state) do
    pre = Map.get(state, :pre)
    account = Map.get(pre, address, %{})
    code = Map.get(account, :code, <<>>)

    byte_size(code)
  end

  def get_code(address, state) do
    pre = Map.get(state, :pre)
    account = Map.get(pre, address, %{})

    Map.get(account, :code, <<>>)
  end

  def return_data(state) do
    Map.get(state, :return_data)
  end

  def inc_cp(state) do
    cp = Map.get(state, :cp)
    Map.put(state, :cp, cp + 1)
  end

  def calculate_blockhash(nth_block, _a, state) do
    # TODO: h -> header, maybe needs refactoring for an actual blockchain
    current_number = current_number(state)

    cond do
      nth_block >= current_number ->
        0

      _a == 256 ->
        0

      # h == 0 -> 0

      current_number - 256 > nth_block ->
        0

      true ->
        bin_nth_block = <<nth_block::256>>
        hash = Aevm.sha3_hash(bin_nth_block)
        <<value::integer-unsigned-256>> = hash
        value
    end
  end

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

  def init_storage(address, pre) do
    case Map.get(pre, address, nil) do
      nil -> %{}
      %{:storage => storage} -> storage
    end
  end

  defp export_exec(gas, to, value, data, caller, dest, state) do
    %{
      :address => dest,
      :origin => State.origin(state),
      :caller => caller,
      :data => data,
      :code => state |> Map.get(:pre, %{to => %{:code => <<>>}}) |> Map.get(to) |> Map.get(:code),
      :gasPrice => State.gas_price(state),
      :gas => gas,
      :value => value
    }
  end

  defp export_env(state) do
    %{
      :currentCoinbase => State.current_coinbase(state),
      :currentDifficulty => State.current_difficulty(state),
      :currentGasLimit => State.current_gas_limit(state),
      :currentNumber => State.current_number(state),
      :currentTimestamp => State.current_timestamp(state)
    }
  end
end
