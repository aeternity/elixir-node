defmodule Aevm do
  use Bitwise

  require OpCodes
  require GasCodes
  require OpCodesUtil
  require AevmConst

  def loop(state) do
    state1 = load_jumpdests(state)
    loop1(state1)
  end

  defp loop1(state) do
    cp = State.cp(state)
    code = State.code(state)

    if cp >= byte_size(code) do
      {:ok, state}
    else
      op_code = get_op_code(state)
      op_name = OpCodesUtil.mnemonic(op_code)

      dynamic_gas_cost = Gas.dynamic_gas_cost(op_name, state)
      state1 = exec(op_code, state)

      mem_gas_cost = Gas.memory_gas_cost(state1, state)
      op_gas_cost = Gas.op_gas_cost(op_code)

      gas_cost = mem_gas_cost + dynamic_gas_cost + op_gas_cost

      state2 =
        if !Enum.member?([OpCodes._CALL(), OpCodes._CALLCODE(), OpCodes._DELEGATECALL()], op_code) do
          Gas.update_gas(gas_cost, state1)
        else
          state1
        end

      state3 = State.inc_cp(state2)

      loop1(state3)
    end
  end

  # 0s: Stop and Arithmetic Operations

  defp exec(OpCodes._STOP(), state) do
    stop_exec(state)
  end

  defp exec(OpCodes._ADD(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 + op2 &&& AevmConst.mask256()

    push(result, state)
  end

  defp exec(OpCodes._MUL(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 * op2 &&& AevmConst.mask256()

    push(result, state)
  end

  defp exec(OpCodes._SUB(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 - op2 &&& AevmConst.mask256()

    push(result, state)
  end

  defp exec(OpCodes._DIV(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        Integer.floor_div(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._SDIV(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        sdiv(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._MOD(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        rem(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._SMOD(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op2 == 0 do
        0
      else
        smod(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._ADDMOD(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)
    {op3, state} = pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 + op2, op3)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._MULMOD(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)
    {op3, state} = pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 * op2, op3)
      end

    masked = result &&& AevmConst.mask256()

    push(masked, state)
  end

  defp exec(OpCodes._EXP(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = exp(op1, op2)

    push(result, state)
  end

  defp exec(OpCodes._SIGNEXTEND(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = signextend(op1, op2)

    push(result, state)
  end

  # 10s: Comparison & Bitwise Logic Operations

  defp exec(OpCodes._LT(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    push(result, state)
  end

  defp exec(OpCodes._GT(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    push(result, state)
  end

  defp exec(OpCodes._SLT(), state) do
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

    push(result, state)
  end

  defp exec(OpCodes._SGT(), state) do
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

    push(result, state)
  end

  defp exec(OpCodes._EQ(), state) do
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

    push(result, state)
  end

  defp exec(OpCodes._ISZERO(), state) do
    {op1, state} = pop(state)

    result =
      if op1 === 0 do
        1
      else
        0
      end

    push(result, state)
  end

  defp exec(OpCodes._AND(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 &&& op2

    push(result, state)
  end

  defp exec(OpCodes._OR(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ||| op2

    push(result, state)
  end

  defp exec(OpCodes._XOR(), state) do
    {op1, state} = pop(state)
    {op2, state} = pop(state)

    result = op1 ^^^ op2

    push(result, state)
  end

  defp exec(OpCodes._NOT(), state) do
    {op1, state} = pop(state)

    result = bnot(op1) &&& AevmConst.mask256()

    push(result, state)
  end

  defp exec(OpCodes._BYTE(), state) do
    {byte, state} = pop(state)
    {value, state} = pop(state)

    result = byte(byte, value)

    push(result, state)
  end

  # 20s: SHA3

  defp exec(OpCodes._SHA3(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)

    {value, state3} = Memory.get_area(from_pos, nbytes, state2)
    sha3hash = sha3_hash(value)
    <<hash::integer-unsigned-256>> = sha3hash
    push(hash, state3)
  end

  # 30s: Environmental Information

  defp exec(OpCodes._ADDRESS(), state) do
    address = State.address(state)
    push(address, state)
  end

  defp exec(OpCodes._BALANCE(), state) do
    {address, state} = pop(state)

    result = State.get_balance(address, state)

    push(result, state)
  end

  defp exec(OpCodes._ORIGIN(), state) do
    origin = State.origin(state)
    push(origin, state)
  end

  defp exec(OpCodes._CALLER(), state) do
    caller = State.caller(state)
    push(caller, state)
  end

  defp exec(OpCodes._CALLVALUE(), state) do
    value = State.value(state)
    push(value, state)
  end

  defp exec(OpCodes._CALLDATALOAD(), state) do
    {address, state1} = pop(state)
    value = value_from_data(address, state1)
    push(value, state1)
  end

  defp exec(OpCodes._CALLDATASIZE(), state) do
    data = State.data(state)
    value = byte_size(data)
    push(value, state)
  end

  defp exec(OpCodes._CALLDATACOPY(), state) do
    {nbytes, state1} = pop(state)
    {from_data_pos, state2} = pop(state1)
    {to_data_pos, state3} = pop(state2)

    data = State.data(state)
    data_bytes = copy_bytes(from_data_pos, to_data_pos, data)
    Memory.write_area(nbytes, data_bytes, state3)
  end

  defp exec(OpCodes._CODESIZE(), state) do
    code = State.code(state)
    value = byte_size(code)
    push(value, state)
  end

  defp exec(OpCodes._CODECOPY(), state) do
    {nbytes, state1} = pop(state)
    {from_code_pos, state2} = pop(state1)
    {to_code_pos, state3} = pop(state2)

    code = State.code(state)
    code_bytes = copy_bytes(from_code_pos, to_code_pos, code)
    Memory.write_area(nbytes, code_bytes, state3)
  end

  defp exec(OpCodes._GASPRICE(), state) do
    gasPrice = State.gasPrice(state)
    push(gasPrice, state)
  end

  defp exec(OpCodes._EXTCODESIZE(), state) do
    {address, state} = pop(state)

    ext_code_size = State.get_ext_code_size(address, state)

    push(ext_code_size, state)
  end

  defp exec(OpCodes._EXTCODECOPY(), state) do
    {address, state1} = pop(state)
    {nbytes, state2} = pop(state1)
    {from_code_pos, state3} = pop(state2)
    {to_code_pos, state4} = pop(state3)

    code = State.get_code(address, state)
    code_bytes = copy_bytes(from_code_pos, to_code_pos, code)
    Memory.write_area(nbytes, code_bytes, state4)
  end

  defp exec(OpCodes._RETURNDATASIZE(), state) do
    #Not sure what "output data from the previous call from the current env" means
    return_data = State.return_data(state)
    value = byte_size(return_data)
    push(value, state)
  end

  defp exec(OpCodes._RETURNDATACOPY(), state) do
    {nbytes, state1} = pop(state)
    {from_rdata_pos, state2} = pop(state1)
    {to_rdata_pos, state3} = pop(state2)

    return_data = State.data(state)
    return_data_bytes = copy_bytes(from_rdata_pos, to_rdata_pos, return_data)
    Memory.write_area(nbytes, return_data_bytes, state3)
  end

  # 40s: Block Information

  defp exec(OpCodes._BLOCKHASH(), state) do
    # Get the hash of one of the 256 most
    # recent complete blocks.
    # µ's[0] ≡ P(IHp, µs[0], 0)
    # where P is the hash of a block of a particular number,
    # up to a maximum age.
    # 0 is left on the stack if the looked for block number
    # is greater than the current block number
    # or more than 256 blocks behind the current block.
    #               0 if n > Hi ∨ a = 256 ∨ h = 0
    # P(h, n, a) ≡  h if n = Hi
    #               P(Hp, n, a + 1) otherwise
    # and we assert the header H can be determined as
    # its hash is the parent hash
    # in the block following it.
    {nth_block, state1} = pop(state)
    hash = State.calculate_blockhash(nth_block, 0, state1)

    push(hash, state1)
  end

  defp exec(OpCodes._COINBASE(), state) do
    currentCoinbase = State.currentCoinbase(state)
    push(currentCoinbase, state)
  end

  defp exec(OpCodes._TIMESTAMP(), state) do
    currentTimestamp = State.currentTimestamp(state)
    push(currentTimestamp, state)
  end

  defp exec(OpCodes._NUMBER(), state) do
    currentNumber = State.currentNumber(state)
    push(currentNumber, state)
  end

  defp exec(OpCodes._DIFFICULTY(), state) do
    currentDifficulty = State.currentDifficulty(state)
    push(currentDifficulty, state)
  end

  defp exec(OpCodes._GASLIMIT(), state) do
    currentGasLimit = State.currentGasLimit(state)
    push(currentGasLimit, state)
  end

  # 50s: Stack, Memory, Storage and Flow Operations

  defp exec(OpCodes._POP(), state) do
    {_, state} = pop(state)

    state
  end

  defp exec(OpCodes._MLOAD(), state) do
    {address, state} = pop(state)

    {result, state1} = Memory.load(address, state)

    push(result, state1)
  end

  defp exec(OpCodes._MSTORE(), state) do
    {address, state} = pop(state)
    {value, state} = pop(state)

    Memory.store(address, value, state)
  end

  defp exec(OpCodes._MSTORE8(), state) do
    {address, state} = pop(state)
    {value, state} = pop(state)

    Memory.store8(address, value, state)
  end

  defp exec(OpCodes._SLOAD(), state) do
    {address, state} = pop(state)

    result = Storage.sload(address, state)

    push(result, state)
  end

  defp exec(OpCodes._SSTORE(), state) do
    {key, state} = pop(state)
    {value, state} = pop(state)
    Storage.sstore(key, value, state)
  end

  defp exec(OpCodes._JUMP(), state) do
    {position, state} = pop(state)
    jumpdests = State.jumpdests(state)

    if Enum.member?(jumpdests, position) do
      jumpdest_cost = Gas.op_gas_cost(OpCodes._JUMPDEST())
      state1 = Gas.update_gas(jumpdest_cost, state)
      State.set_cp(position, state1)
    else
      throw({:error, "invalid_jump_dest, #{position}", state})
    end
  end

  defp exec(OpCodes._JUMPI(), state) do
    {position, state} = pop(state)
    {condition, state} = pop(state)

    jumpdests = State.jumpdests(state)

    if condition !== 0 do
      if Enum.member?(jumpdests, position) do
        jumpdest_cost = Gas.op_gas_cost(OpCodes._JUMPDEST())
        state1 = Gas.update_gas(jumpdest_cost, state)
        State.set_cp(position, state1)
      else
        throw({:error, "invalid_jump_dest, #{position}", state})
      end
    else
      state
    end
  end

  defp exec(OpCodes._PC(), state) do
    pc = State.cp(state)
    push(pc, state)
  end

  defp exec(OpCodes._MSIZE(), state) do
    result = Memory.memory_size_bytes(state)

    push(result, state)
  end

  defp exec(OpCodes._GAS(), state) do
    gas_cost = Gas.op_gas_cost(OpCodes._GAS())
    gas = State.gas(state) - gas_cost
    push(gas, state)
  end

  defp exec(OpCodes._JUMPDEST(), state) do
    state
  end

  # 60s & 70s: Push Operations

  defp exec(OpCodes._PUSH1() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH2() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH3() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH4() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH5() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH6() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH7() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH8() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH9() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH10() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH11() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH12() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH13() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH14() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH15() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH16() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH17() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH18() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH19() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH20() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH21() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH22() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH23() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH24() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH25() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH26() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH27() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH28() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH29() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH30() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH31() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  defp exec(OpCodes._PUSH32() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = move_cp_n_bytes(bytes, state)

    push(result, state1)
  end

  # 80s: Duplication Operations

  defp exec(OpCodes._DUP1() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP2() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP3() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP4() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP5() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP6() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP7() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP8() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP9() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP10() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP11() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP12() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP13() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP14() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP15() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  defp exec(OpCodes._DUP16() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    dup(slot, state)
  end

  # 90s: Exchange Operations

  defp exec(OpCodes._SWAP1() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP2() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP3() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP4() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP5() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP6() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP7() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP8() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP9() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP10() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP11() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP12() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP13() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP14() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP15() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  defp exec(OpCodes._SWAP16() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    swap(bytes, state)
  end

  # a0s: Logging Operations

  defp exec(OpCodes._LOG0(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)

    log([], from_pos, nbytes, state2)
  end

  defp exec(OpCodes._LOG1(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)
    {topic1, state3} = pop(state2)

    log([topic1], from_pos, nbytes, state3)
  end

  defp exec(OpCodes._LOG2(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)
    {topic1, state3} = pop(state2)
    {topic2, state4} = pop(state3)

    log([topic1, topic2], from_pos, nbytes, state4)
  end

  defp exec(OpCodes._LOG3(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)
    {topic1, state3} = pop(state2)
    {topic2, state4} = pop(state3)
    {topic3, state5} = pop(state4)

    log([topic1, topic2, topic3], from_pos, nbytes, state5)
  end

  defp exec(OpCodes._LOG4(), state) do
    {from_pos, state1} = pop(state)
    {nbytes, state2} = pop(state1)
    {topic1, state3} = pop(state2)
    {topic2, state4} = pop(state3)
    {topic3, state5} = pop(state4)
    {topic4, state6} = pop(state5)

    log([topic1, topic2, topic3, topic4], from_pos, nbytes, state6)
  end

  # f0s: System operations

  defp exec(OpCodes._CREATE(), state) do
    {value, state1} = pop(state)
    {from_pos, state2} = pop(state1)
    {size, state3} = pop(state2)

    {area, state4} = Memory.get_area(from_pos, size, state3)
    {account, state5} = create_account(value, area, state4)

    push(account, state5)
  end

  defp exec(OpCodes._CALL(), state) do
    {return, state1} = call(state, OpCodes._CALL())
    push(return, state1)
  end

  defp exec(OpCodes._CALLCODE(), state) do
    {return, state1} = call(state, OpCodes._CALL())
    push(return, state1)
  end

  defp exec(OpCodes._RETURN(), state) do
    {from_pos, state} = pop(state)
    {nbytes, state} = pop(state)

    {result, state1} = Memory.get_area(from_pos, nbytes, state)

    state2 = State.set_out(result, state1)
    stop_exec(state2)
  end

  defp exec(OpCodes._DELEGATECALL(), state) do
    {return, state1} = call(state, OpCodes._CALL())
    push(return, state1)
  end

  # defp exec(OpCodes._CALLBLACKBOX(), state) do
  #   # TODO
  # end

  # defp exec(OpCodes._STATICCALL(), state) do
  #   # TODO
  # end

  # defp exec(OpCodes._REVERT(), state) do
  #   # TODO
  # end

  defp exec(OpCodes._INVALID(), state) do
    throw({:error, "invalid instruction", state})
  end

  # Halt Execution, Mark for deletion

  defp exec(OpCodes._SUICIDE(), state) do
    {value, state1} = pop(state)
    state2 = State.set_selfdestruct(value, state1)

    # mem_gas_cost = Gas.memory_gas_cost(state1, state)
    # State.set_gas()

    stop_exec(state2)
  end

  defp exec([], state) do
    state
  end

  #
  # Util functions
  #

  defp stop_exec(state) do
    code = State.code(state)
    State.set_cp(byte_size(code), state)
  end

  defp sdiv(_value1, 0), do: 0
  defp sdiv(0, -1), do: AevmConst.neg2to255()

  defp sdiv(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    div(svalue1, svalue2) &&& AevmConst.mask256()
  end

  defp smod(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    result = rem(rem(svalue1, svalue2 + svalue2), svalue2)
    result &&& AevmConst.mask256()
  end

  defp pow(op1, op2) when is_integer(op1) and is_integer(op2) and op2 >= 0, do: pow(1, op1, op2)

  defp pow(n, _, 0), do: n
  defp pow(n, op1, 1), do: op1 * n

  defp pow(n, op1, op2) do
    square = op1 * op1 &&& AevmConst.mask256()
    exp = op2 >>> 1

    case op2 &&& 1 do
      0 -> pow(n, square, exp)
      _ -> pow(op1 * n, square, exp)
    end
  end

  defp exp(op1, op2) do
    pow(op1, op2) &&& AevmConst.mask256()
  end

  defp signed(value) do
    <<svalue::integer-signed-256>> = <<value::integer-unsigned-256>>
    svalue
  end

  defp byte(byte, value) when byte < 32 do
    byte_pos = 256 - 8 * (byte + 1)
    mask = 255
    value >>> byte_pos &&& mask
  end

  defp byte(_, _), do: 0

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

  defp get_op_code(state) do
    cp = State.cp(state)
    code = State.code(state)
    prev_bits = cp * 8

    <<_::size(prev_bits), op_code::size(8), _::binary>> = code

    op_code
  end

  defp move_cp_n_bytes(bytes, state) do
    old_cp = State.cp(state)
    code = State.code(state)

    curr_cp = old_cp + 1
    prev_bits = curr_cp * 8
    value_size_bits = bytes * 8
    code_byte_size = byte_size(code)

    value =
      cond do
        curr_cp > code_byte_size ->
          0

        curr_cp + bytes >= code_byte_size ->
          extend = (curr_cp + bytes - code_byte_size) * 8
          <<_::size(prev_bits), value::size(value_size_bits)>> = <<code::binary, 0::size(extend)>>
          value

        true ->
          <<_::size(prev_bits), value::size(value_size_bits), _::binary>> = code
          value
      end

    state1 = State.set_cp(old_cp + bytes, state)

    {value, state1}
  end

  defp create_account(_value, _area, state) do
    # TODO
    {0xDEADC0DE, state}
  end

  defp copy_bytes(from_byte, n, bin_data) do
    size = byte_size(bin_data)
    bit_pos = from_byte * 8

    cond do
      from_byte + n >= size && from_byte > size ->
        byteSize = n * 8
        <<0::size(byteSize)>>

      from_byte + n >= size ->
        extend = (n - (size - from_byte)) * 8

        <<_::size(bit_pos), copy::size(n)-binary, _::binary>> =
          <<bin_data::binary, 0::size(extend)>>

        copy

      true ->
        <<_::size(bit_pos), copy::size(n)-binary, _::binary>> = bin_data
        copy
    end
  end

  defp value_from_data(address, state) do
    data = State.data(state)
    data_copy = copy_bytes(address, 32, data)
    <<value::size(256)>> = data_copy
    value
  end

  def sha3_hash(data) when is_binary(data) do
    :sha3.hash(256, data)
  end

  defp load_jumpdests(%{cp: cp, code: code} = state) when cp >= byte_size(code) do
    State.set_cp(0, state)
  end

  defp load_jumpdests(state) do
    cp = State.cp(state)

    op_code = get_op_code(state)

    state1 =
      cond do
        op_code == OpCodes._JUMPDEST() ->
          jumpdests = State.jumpdests(state)
          %{state | jumpdests: [cp | jumpdests]}

        op_code >= OpCodes._PUSH1() && op_code <= OpCodes._PUSH32() ->
          bytes = op_code - OpCodes._PUSH1() + 1
          {_, state1} = move_cp_n_bytes(bytes, state)
          state1

        true ->
          state
      end

    state2 = State.inc_cp(state1)
    load_jumpdests(state2)
  end

  defp log(topics, from_pos, nbytes, state) do
    account = State.address(state)
    {memory_area, state1} = Memory.get_area(from_pos, nbytes, state)
    logs = State.logs(state)

    topics_joined =
      Enum.reduce(topics, <<>>, fn topic, acc ->
        acc <> <<topic::256>>
      end)

    log = <<account::256>> <> topics_joined <> memory_area

    State.set_logs([log | logs], state1)
  end

  defp signextend(op1, op2) do
    extend_to = 256 - 8 * (op1 + 1 &&& 255) &&& 255
    <<_::size(extend_to), sign_bit::size(1), trunc_val::bits>> = <<op2::integer-unsigned-256>>

    pad =
      if extend_to == 0 do
        <<>>
      else
        for _ <- 1..extend_to, into: <<>>, do: <<sign_bit::1>>
      end

    <<val::integer-unsigned-256>> = <<pad::bits, sign_bit::1, trunc_val::bits>>
    val
  end

  defp call(state, op_code) do
    if State.calldepth(state) < 1024 do
      call1(state, op_code)
    else
      {0, state}
    end
  end

  defp call1(state, op_code) do
    {gas, state1} = pop(state)
    {to, state2} = pop(state1)
    {value, state3} = determine_call_value(state2, op_code)
    {in_offset, state4} = pop(state3)
    {in_size, state5} = pop(state4)
    {out_offset, state6} = pop(state5)
    {out_size, state7} = pop(state6)

    # check gas
    op_code = get_op_code(state7)
    op_name = OpCodesUtil.mnemonic(op_code)
    dynamic_gas_cost = Gas.dynamic_gas_cost(op_name, state)
    mem_gas_cost = Gas.memory_gas_cost(state7, state)
    op_gas_cost = Gas.op_gas_cost(op_code)
    gas_cost = mem_gas_cost + dynamic_gas_cost + op_gas_cost
    state8 = Gas.update_gas(gas_cost, state7)

    {in_area, state9} = Memory.get_area(in_offset, in_size, state8)
    call_gas = adjust_call_gas(gas, value)
    caller = determine_call_caller(state9, op_code)
    dest = determine_call_dest(state, op_code)

    call_state =
      State.init_for_call(call_gas, to, value, in_area, caller, dest, state9, %{
        default_opts()
        | :execute_calls => State.execute_calls(state9)
      })

    return_state =
      if State.execute_calls(call_state) do
        {ret, out_gas} =
          try do
            {:ok, out_state} = loop(call_state)
            {:ok, State.gas(out_state)}
          catch
            {:error, _, _} ->
              {:error, 0}
          end

        remaining_gas = State.gas(state9) + out_gas
        return_state1 = State.set_gas(remaining_gas, state9)
        return_state2 = State.add_callcreate(in_area, dest, call_gas, value, return_state1)
        case ret do
          :ok ->
            {message, _} = Memory.get_area(0, out_size, return_state2)
            return_state3 = Memory.write_area(out_offset, message, return_state2)
            mem_gas_cost = Gas.memory_gas_cost(return_state3, return_state2)
            State.set_gas(remaining_gas - mem_gas_cost, return_state3)

          :error ->
            return_state2
        end
      else
        remaining_gas = State.gas(state9) + call_gas
        state10 = State.set_gas(remaining_gas, state9)
        State.add_callcreate(in_area, dest, call_gas, value, state10)
      end

    {1, return_state}
  end

  defp determine_call_value(state, op_code) do
    case op_code do
      OpCodes._CALL() ->
        pop(state)
      OpCodes._CALLCODE() ->
        pop(state)
      OpCodes._DELEGATECALL() ->
        {State.value(state), state}
    end
  end

  defp determine_call_caller(state, op_code) do
    case op_code do
      OpCodes._CALL() ->
        State.address(state)
      OpCodes._CALLCODE() ->
        State.address(state)
      OpCodes._DELEGATECALL() ->
        State.caller(state)
    end
  end

  defp determine_call_dest(state, op_code) do
    case op_code do
      OpCodes._CALL() ->
        Stack.peek(1, state)
      OpCodes._CALLCODE() ->
        State.address(state)
      OpCodes._DELEGATECALL() ->
        State.address(state)
    end
  end

  defp adjust_call_gas(gas, value) do
    if value != 0 do
      gas + GasCodes._GCALLSTIPEND()
    else
      gas
    end
  end

  defp default_opts() do
    %{
      :execute_calls => true
    }
  end
end
