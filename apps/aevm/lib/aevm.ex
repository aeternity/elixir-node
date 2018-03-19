defmodule Aevm do

  use Bitwise

  require OpCodes
  require OpCodesUtil

  require AevmStack

  def chunk_bytecode(bytecode) do
    chunked_bytecode =
      bytecode
      |> String.to_charlist
      |> Enum.chunk_every(2)
      |> Enum.reduce([], fn(x, acc) ->
        {code, _} = x |> List.to_string |> Integer.parse(16)

        [code | acc]
      end)
      |> Enum.reverse()
  end

  def exec([OpCodes._STOP | op_codes], stack) do
    stack
  end

  def exec([OpCodes._ADD | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 + op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._MUL | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 * op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SUB | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 - op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._DIV | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op2 == 0 do
        0
      else
        op1 / op2
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SDIV | op_codes], stack) do
    # TODO: check calculation
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op2 == 0 do
        0
      else
        op1 / op2
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._MOD | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op2 == 0 do
        0
      else
        rem(op1, op2)
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SMOD | op_codes], stack) do
    # TODO: check calculation
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op2 == 0 do
        0
      else
        rem(op1, op2)
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._ADDMOD | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)
    {op3, stack} = AevmStack.pop(stack)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 + op2, op3)
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._MULMOD | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)
    {op3, stack} = AevmStack.pop(stack)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 * op2, op3)
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._EXP | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = :math.pow(op1, op2)

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SIGNEXTEND | op_codes], stack) do
    # TODO
  end

  def exec([OpCodes._LT | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._GT | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SLT | op_codes], stack) do
    # TODO: check calculation
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._SGT | op_codes], stack) do
    # TODO: check calculation
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._EQ | op_codes], stack) do
    # TODO: check calculation
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result =
      if op1 == op2 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._ISZERO | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)

    result =
      if op1 === 0 do
        1
      else
        0
      end

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._AND | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 &&& op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._OR | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 ||| op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._XOR | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    result = op1 ^^^ op2

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._NOT | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)

    result = bnot(op1)

    exec(op_codes, AevmStack.push(stack, result))
  end

  def exec([OpCodes._BYTE | op_codes], stack) do
    # TODO
  end

  def exec([OpCodes._SHA3 | op_codes], stack) do
    # TODO
  end



  # --------------------------------------------------

  def exec([OpCodes._PUSH1 = current_op | op_codes], stack) do
    {op_code, popped, _pushed} = OpCodesUtil.opcode(current_op)

    [val | rem_op_codes] = op_codes

    exec(rem_op_codes, AevmStack.push(stack, val))
  end

  def exec([], stack) do
    stack
  end

end
