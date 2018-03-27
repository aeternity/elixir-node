defmodule Aevm do
  use Bitwise

  require OpCodes
  require OpCodesUtil
  require AevmConst
  require Stack

  # 0s: Stop and Arithmetic Operations

  def exec([OpCodes._STOP() | op_codes], state) do
    state
  end

  def exec([OpCodes._ADD() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 + op2

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._MUL() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 * op2

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._SUB() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 - op2

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._EXP() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = :math.pow(op1, op2)

    exec(op_codes, push(result, state))
  end

  # not working correctly
  def exec([OpCodes._SIGNEXTEND() | op_codes], state) do
    # TODO
    # {op1, state} = pop(state)
    # {op2, state} = pop(state)
    #
    # result = signextend(op2, op1)
    #
    # exec(op_codes, push(result, state))
  end

  # 10s: Comparison & Bitwise Logic Operations

  def exec([OpCodes._LT() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    exec(op_codes, push(result, state))
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

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._SLT() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    sop1 = signed(op1)
    sop2 = signed(op2)

    result =
      if sop1 < sop2 do
        1
      else
        0
      end

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._SGT() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    sop1 = signed(op1)
    sop2 = signed(op2)

    result =
      if sop1 > sop2 do
        1
      else
        0
      end

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._EQ() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    sop1 = signed(op1)
    sop2 = signed(op2)

    result =
      if sop1 == sop2 do
        1
      else
        0
      end

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._ISZERO() | op_codes], state) do
    {op1, state} = pop(state)

    result =
      if op1 === 0 do
        1
      else
        0
      end

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._AND() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 &&& op2

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._OR() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ||| op2

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._XOR() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ^^^ op2

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._NOT() | op_codes], state) do
    {op1, state} = pop(state)

    result = bnot(op1)

    exec(op_codes, push(result, state))
  end

  def exec([OpCodes._BYTE() | op_codes], state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = byte(op1, op2)

    exec(op_codes, push(state, result))
  end

  # 20s: SHA3

  def exec([OpCodes._SHA3() | op_codes], state) do
    # TODO
  end

  ## TODO: Add exec() for #30s and 40s
  # ---------------------------------------------------

  # 50s: Stack, Memory, Storage and Flow Operations

  def exec([OpCodes._POP() | op_codes], state) do
    {_, state} = pop(state)

    exec(op_codes, state)
  end

  def exec([OpCodes._MLOAD() | op_codes], state) do
    {address, state} = pop(state)

    result = Memory.load(address, state)
    state1 = push(result, state)

    exec(op_codes, state1)
  end

  def exec([OpCodes._MSTORE() | op_codes], state) do
    {address, state} = pop(state)
    {value, state} = pop(state)

    state1 = Memory.store(address, value, state)

    exec(op_codes, state1)
  end

  def exec([OpCodes._MSTORE8() | op_codes], state) do
    {address, state} = pop(state)
    {value, state} = pop(state)

    state1 = Memory.store8(address, value, state)

    exec(op_codes, state1)
  end

  def exec([OpCodes._SLOAD() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SSTORE() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._JUMP() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._JUMPI() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PC() | op_codes], state) do
  end

  def exec([OpCodes._MSIZE() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._GAS() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._JUMPDEST() | op_codes], state) do
    # TODO
  end

  # 60s & 70s: Push Operations

  def exec([OpCodes._PUSH1() = current_op | op_codes], state) do
    {op_code, popped, _pushed} = OpCodesUtil.opcode(current_op)

    [result | rem_op_codes] = op_codes

    exec(rem_op_codes, push(result, state))
  end

  def exec([OpCodes._PUSH2() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH3() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH4() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH5() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH6() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH7() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH8() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH9() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH10() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH11() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH12() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH13() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH14() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH15() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH16() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH17() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH18() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH19() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH20() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH21() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH22() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH23() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH24() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH25() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH26() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH27() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH28() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH29() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH30() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH31() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._PUSH32() | op_codes], state) do
    # TODO
  end

  # 80s: Duplication Operations

  def exec([OpCodes._DUP1() = current_op | op_codes], state) do
    # TODO:
    # {op_code, _popped, pushed} = OpCodesUtil.opcode(current_op)

    # hardcoded for now, testing purposes
    # exec(op_codes, dup(state, 1))
  end

  def exec([OpCodes._DUP2() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP3() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP4() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP5() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP6() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP7() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP8() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP9() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP10() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP11() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP12() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP13() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP14() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP15() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DUP16() | op_codes], state) do
    # TODO
  end

  # 90s: Exchange Operations

  def exec([OpCodes._SWAP1() = current_op | op_codes], state) do
    # TODO:
    # {op_code, _popped, pushed} = OpCodesUtil.opcode(current_op)

    # hardcoded for now, testing purposes
    # exec(op_codes, swap(state, 1))
  end

  def exec([OpCodes._SWAP2() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP3() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP4() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP5() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP6() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP7() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP8() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP9() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP10() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP11() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP12() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP13() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP14() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP15() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._SWAP16() | op_codes], state) do
    # TODO
  end

  # a0s: Logging Operations

  def exec([OpCodes._LOG0() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._LOG1() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._LOG2() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._LOG3() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._LOG4() | op_codes], state) do
    # TODO
  end

  # f0s: System operations

  def exec([OpCodes._CREATE() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._CALL() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._CALLCODE() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._RETURN() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._DELEGATECALL() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._CALLBLACKBOX() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._STATICCALL() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._REVERT() | op_codes], state) do
    # TODO
  end

  def exec([OpCodes._INVALID() | op_codes], state) do
    # TODO
  end

  # Halt Execution, Mark for deletion

  def exec([OpCodes._SUICIDE() | op_codes], state) do
    # TODO
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

  defp signed(value) do
    <<svalue::integer-signed-256>> = <<value::integer-unsigned-256>>
    svalue
  end

  defp byte(byte, value) when byte < 32 do
    byte_pos = 256 - 8 * (byte + 1)
    mask = 255
    Bitwise.band(Bitwise.bsr(value, byte_pos), mask)
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

  defp push(value, state) do
    Stack.push(value, state)
  end

  defp pop(state) do
    Stack.pop(state)
  end

  defp dup(index, state) do
    Stack.dup(index, state)
  end

  defp swap(index, state) do
    Stack.swap(index, state)
  end
end
