defmodule Gas do
  use Bitwise

  require OpCodesUtil
  require GasCodes

  def update_gas(gas_cost, state) do
    curr_gas = State.gas(state)

    if curr_gas >= gas_cost do
      gas_after = curr_gas - gas_cost
      State.set_gas(gas_after, state)
    else
      throw({:error, "out_of_gas", state})
    end
  end

  def op_gas_cost(op_code) do
    {_name, _pushed, _popped, op_gas_price} = OpCodesUtil.opcode(op_code)
    op_gas_price
  end

  def memory_gas_cost(state_with_ops, state_without) do
    words1 = Memory.memory_size_words(state_with_ops)

    case Memory.memory_size_words(state_without) do
      ^words1 ->
        0

      words2 ->
        first = round(GasCodes._GMEMORY() * words1 + Float.floor(words1 * words1 / 512))
        second = round(GasCodes._GMEMORY() * words2 + Float.floor(words2 * words2 / 512))
        first - second
    end
  end

  def dynamic_gas_cost("CALL", state) do
    gas_cost = 0
    # TODO: account creation?
    value = peek(2, state)

    gas_cost = gas_cost +
      if value !== 0 do
        GasCodes._GCALLVALUE()
      else
        0
      end

    gas_cost + GasCodes._GCALL()
  end

  def dynamic_gas_cost("DELEGATECALL", state) do
    # TODO
    0
  end

  def dynamic_gas_cost("CALLDATACOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(peek(2, state) / 32))
  end

  def dynamic_gas_cost("CODECOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(peek(2, state) / 32))
  end

  def dynamic_gas_cost("EXTCODECOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(peek(3, state) / 32))
  end

  def dynamic_gas_cost("LOG0", state) do
    GasCodes._GLOGDATA() * peek(1, state)
  end

  def dynamic_gas_cost("LOG1", state) do
    GasCodes._GLOGDATA() * peek(1, state)
  end

  def dynamic_gas_cost("LOG2", state) do
    GasCodes._GLOGDATA() * peek(1, state)
  end

  def dynamic_gas_cost("LOG3", state) do
    GasCodes._GLOGDATA() * peek(1, state)
  end

  def dynamic_gas_cost("LOG4", state) do
    GasCodes._GLOGDATA() * peek(1, state)
  end

  def dynamic_gas_cost("SHA3", state) do
    peeked = peek(1, state)
    GasCodes._GSHA3WORD() * round(Float.ceil(peeked / 32))
  end

  def dynamic_gas_cost("SSTORE", state) do
    address = peek(0, state)
    value = peek(1, state)
    curr_storage = Storage.sload(address, state)

    if value != 0 && curr_storage === 0 do
      GasCodes._GSSET()
    else
      GasCodes._GSRESET()
    end
  end

  def dynamic_gas_cost("EXP", state) do
    case peek(1, state) do
      0 -> 0
      peeked -> GasCodes._GEXPBYTE() * (1 + log(peeked))
    end
  end

  def dynamic_gas_cost(_op_name, _state) do
    0
  end

  defp peek(index, state) do
    Stack.peek(index, state)
  end

  def log(value) when is_integer(value) do
    log(value, -1)
  end

  def log(0, num), do: num

  def log(value, num) do
    log(Bitwise.bsr(value, 8), num + 1)
  end
end
