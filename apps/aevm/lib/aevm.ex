defmodule Aevm do
  use Bitwise

  require OpCodes
  require OpCodesUtil
  require AevmConst
  require Stack

  def chunk_bytecode(bytecode) do
    chunked_bytecode =
      bytecode
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.reduce([], fn x, acc ->
        {code, _} = x |> List.to_string() |> Integer.parse(16)

        [code | acc]
      end)
      |> Enum.reverse()
  end

  def exec([OpCodes._STOP() | op_codes], state) do
    state
  end

  def exec([OpCodes._ADD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 + op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._MUL() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 * op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._SUB() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 - op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._DIV() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        Integer.floor_div(op1, op2)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._SDIV() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        sdiv(op1, op2)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._MOD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        rem(op1, op2)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._SMOD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        smod(op1, op2)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._ADDMOD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)
    {op3, state} = pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 + op2, op3)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._MULMOD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)
    {op3, state} = pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 * op2, op3)
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._EXP() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = :math.pow(op1, op2)

    exec(op_codes, push(state, result))
  end

  # not working correctly
  def exec([OpCodes._SIGNEXTEND() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = signextend(op2, op1)

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._LT() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._GT() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._SLT() | op_codes], state) do
    # TODO: check calculation
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._SGT() | op_codes], state) do
    # TODO: check calculation
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._EQ() | op_codes], state) do
    # TODO: check calculation
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 == op2 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._ISZERO() | op_codes], state) do
    {op1, state} = pop(state)

    result =
      if op1 === 0 do
        1
      else
        0
      end

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._AND() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 &&& op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._OR() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ||| op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._XOR() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ^^^ op2

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._NOT() | op_codes], state) do
    {op1, state} = pop(state)

    result = bnot(op1)

    exec(op_codes, push(state, result))
  end

  def exec([OpCodes._BYTE() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SHA3() | op_codes], state) do
    # TODO
  end

  # --------------------------------------------------

  def exec([OpCodes._PUSH1() = current_op | op_codes], state) do
    IO.inspect(state.stack)
    {op_code, popped, _pushed} = OpCodesUtil.opcode(current_op)

    [val | rem_op_codes] = op_codes

    exec(rem_op_codes, push(state, val))
  end

  def exec([], state) do
    state
  end

  defp sdiv(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    Bitwise.band(Integer.floor_div(svalue1, svalue2), AevmConst.mask256())
  end

  defp smod(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    result = rem(rem(svalue1, svalue2 + svalue2), svalue2)
    Bitwise.band(result, AevmConst.mask256())
  end

  # defp signextend(value1, value2) do
  #   value1_bits = Aeutil.Bits.extract(<<value1>>)
  #   ext_value1 = extend_bits(value2, value1_bits)
  # end
  #
  # defp extend_bits(number_to_extn_with, list) do
  #   if number_to_extn_with > 0 do
  #     list = List.insert_at(list, 0, List.first(list))
  #     new_list = extend_bits(number_to_extn_with - 1, list)
  #   else
  #     list
  #   end
  # end

  defp push(state, value) do
    Stack.push(state, value)
  end

  defp pop(state) do
    Stack.pop(state)
  end

  defp dup(state, index) do
    Stack.dup(state, index)
  end

  defp swap(state, index) do
    Stack.swap(state, index)
  end
end
