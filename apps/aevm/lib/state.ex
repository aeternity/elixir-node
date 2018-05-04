defmodule State do
  @spec init_vm(map(), map(), map()) :: map()
  def init_vm(exec, env, pre) do
    bytecode = Map.get(exec, :code)
    code_bin = bytecode_to_bin(bytecode)

    %{
      :stack => [],
      :memory => %{size: 0},
      :storage => %{},
      :cp => 0,
      :jumpdests => [],
      :out => <<>>,
      :logs => [],
      # :return_data => return_data,

      :address => Map.get(exec, :address),
      :origin => Map.get(exec, :origin),
      :caller => Map.get(exec, :caller),
      :data => Map.get(exec, :data),
      :code => code_bin,
      :gasPrice => Map.get(exec, :gasPrice),
      :gas => Map.get(exec, :gas),

      :currentCoinbase => Map.get(env, :currentCoinbase),
      :currentDifficulty => Map.get(env, :currentDifficulty),
      :currentGasLimit => Map.get(env, :currentGasLimit),
      :currentNumber => Map.get(env, :currentNumber),
      :currentTimestamp => Map.get(env, :currentTimestamp),
      
      :pre => pre
    }
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

  def gasPrice(state) do
    Map.get(state, :gasPrice)
  end

  def origin(state) do
    Map.get(state, :origin)
  end

  def value(state) do
    Map.get(state, :value)
  end

  def currentCoinbase(state) do
    Map.get(state, :currentCoinbase)
  end

  def currentDifficulty(state) do
    Map.get(state, :currentDifficulty)
  end

  def currentGasLimit(state) do
    Map.get(state, :currentGasLimit)
  end

  def currentNumber(state) do
    Map.get(state, :currentNumber)
  end

  def currentTimestamp(state) do
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

  # def return_data(state) do
  #   Map.get(state, :return_data)
  # end

  def inc_cp(state) do
    cp = Map.get(state, :cp)
    Map.put(state, :cp, cp + 1)
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
end
