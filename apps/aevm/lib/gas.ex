defmodule Gas do
  @moduledoc """
  Module for updating the current gas value and calculating
  the additional costs for the opcodes, based on dynamic data
  """

  use Bitwise

  require OpCodesUtil
  require GasCodes

  @doc """
  Subtract a given `gas_cost` from the current gas in the state
  """
  @spec update_gas(integer(), map()) :: map() | {:error, String.t(), map()}
  def update_gas(gas_cost, state) do
    curr_gas = State.gas(state)

    if curr_gas >= gas_cost do
      gas_after = curr_gas - gas_cost
      State.set_gas(gas_after, state)
    else
      throw({:error, "out_of_gas", state})
    end
  end

  @doc """
  Get the initial gas cost for a given `op_code`
  """
  @spec op_gas_cost(char()) :: integer()
  def op_gas_cost(op_code) do
    {_name, _pushed, _popped, op_gas_price} = OpCodesUtil.opcode(op_code)
    op_gas_price
  end

  @doc """
  Calculate the fee for the expanded memory
  """
  @spec memory_gas_cost(map(), map()) :: integer()
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

  @doc """
  Calculate gas cost for a given opcode, based on some dynamic data
  """
  @spec dynamic_gas_cost(String.t(), map()) :: integer()
  def dynamic_gas_cost("CALL", state) do
    dynamic_call_cost(state)
  end

  def dynamic_gas_cost("DELEGATECALL", state) do
    dynamic_call_cost(state)
  end

  def dynamic_gas_cost("CALLDATACOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(Stack.peek(2, state) / 32))
  end

  def dynamic_gas_cost("CODECOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(Stack.peek(2, state) / 32))
  end

  def dynamic_gas_cost("EXTCODECOPY", state) do
    GasCodes._GCOPY() * round(Float.ceil(Stack.peek(3, state) / 32))
  end

  def dynamic_gas_cost("LOG0", state) do
    GasCodes._GLOGDATA() * Stack.peek(1, state)
  end

  def dynamic_gas_cost("LOG1", state) do
    GasCodes._GLOGDATA() * Stack.peek(1, state)
  end

  def dynamic_gas_cost("LOG2", state) do
    GasCodes._GLOGDATA() * Stack.peek(1, state)
  end

  def dynamic_gas_cost("LOG3", state) do
    GasCodes._GLOGDATA() * Stack.peek(1, state)
  end

  def dynamic_gas_cost("LOG4", state) do
    GasCodes._GLOGDATA() * Stack.peek(1, state)
  end

  def dynamic_gas_cost("SHA3", state) do
    peeked = Stack.peek(1, state)
    GasCodes._GSHA3WORD() * round(Float.ceil(peeked / 32))
  end

  def dynamic_gas_cost("SSTORE", state) do
    address = Stack.peek(0, state)
    value = Stack.peek(1, state)
    curr_storage = Storage.sload(address, state)

    if value != 0 && curr_storage === 0 do
      GasCodes._GSSET()
    else
      GasCodes._GSRESET()
    end
  end

  def dynamic_gas_cost("EXP", state) do
    case Stack.peek(1, state) do
      0 -> 0
      peeked -> GasCodes._GEXPBYTE() * (1 + log(peeked))
    end
  end

  def dynamic_gas_cost(_op_name, _state) do
    0
  end

  # Determine the gas cost for a CALL instruction

  defp dynamic_call_cost(state) do
    gas_cost_0 = GasCodes._GCALL()

    gas_state = State.gas(state)
    gas = Stack.peek(0, state)
    value = Stack.peek(2, state)

    gas_cost_1 =
      gas_cost_0 +
        if value !== 0 do
          GasCodes._GCALLVALUE()
        else
          0
        end

    gas_cost_1 +
      if gas_state >= gas_cost_1 do
        gas_one_64_substracted = substract_one_64(gas_state - gas_cost_1)

        if gas < gas_one_64_substracted do
          gas
        else
          gas_one_64_substracted
        end
      else
        gas
      end
  end

  defp log(value) when is_integer(value) do
    log(value, -1)
  end

  defp log(0, num), do: num

  defp log(value, num) do
    log(Bitwise.bsr(value, 8), num + 1)
  end

  defp substract_one_64(value) do
    one_64th = value / 64
    rounded_64th = one_64th |> Float.floor() |> round()
    value - rounded_64th
  end
end
