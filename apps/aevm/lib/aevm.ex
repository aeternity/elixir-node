defmodule Aevm do

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
    # bytecode_to_opcodes(chunked_bytecode, "")
  end

  def exec([OpCodes._PUSH1 = current_op | op_codes], stack) do
    {op_code, popped, _pushed} = OpCodesUtil.opcode(current_op)

    [val | rem_op_codes] = op_codes

    exec(rem_op_codes, AevmStack.push(stack, val))
  end

  def exec([OpCodes._ADD | op_codes], stack) do
    {op1, stack} = AevmStack.pop(stack)
    {op2, stack} = AevmStack.pop(stack)

    exec(op_codes, AevmStack.push(stack, op1 + op2))
  end

  def exec([], stack) do
    stack
  end

  def bytecode_to_opcodes([current_op | op_codes], result) do
    {op_code, popped, _pushed} = OpCodesUtil.opcode(current_op)

    # if popped > 1 && is push -> take as a whole; else - iterate as each as another op code

    op_code_param =
      op_codes
      |> Enum.slice(0, popped)
      |> Enum.reduce("", fn(x, acc) ->
        param_as_hex = x |> Integer.to_charlist(16) |> List.to_string() |> String.downcase()

        acc <> param_as_hex
      end)

    result = result <> " " <> op_code <> " 0x" <> op_code_param
    IO.inspect(result)

    bytecode_to_opcodes(Enum.drop(op_codes, popped), result)
  end

  def bytecode_to_opcodes([], result) do
    result
  end

end
