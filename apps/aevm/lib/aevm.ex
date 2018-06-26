defmodule Aevm do
  @moduledoc """
    Module for the execution of a contract
  """

  use Bitwise

  require OpCodes
  require OpCodesUtil
  require AevmConst

  @spec loop(map()) :: map()
  def loop(state) do
    state1 = AevmUtil.load_jumpdests(state)
    loop1(state1)
  end

  defp loop1(state) do
    pc = State.pc(state)
    code = State.code(state)

    if pc >= byte_size(code) do
      {:ok, state}
    else
      op_code = AevmUtil.get_op_code(state)
      op_name = OpCodesUtil.mnemonic(op_code)

      dynamic_gas_cost = Gas.dynamic_gas_cost(op_name, state)
      state_after_exec = exec(op_code, state)

      mem_gas_cost = Gas.memory_gas_cost(state_after_exec, state)
      op_gas_cost = Gas.op_gas_cost(op_code)

      gas_cost = mem_gas_cost + dynamic_gas_cost + op_gas_cost

      updated_gas_state =
        if Enum.member?([OpCodes._CALL(), OpCodes._CALLCODE(), OpCodes._DELEGATECALL()], op_code) do
          state_after_exec
        else
          Gas.update_gas(gas_cost, state_after_exec)
        end

      updated_pc_state = State.inc_pc(updated_gas_state)

      loop1(updated_pc_state)
    end
  end

  # 0s: Stop and Arithmetic Operations

  defp exec(OpCodes._STOP(), state) do
    AevmUtil.stop_exec(state)
  end

  defp exec(OpCodes._ADD(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 + op2 &&& AevmConst.mask256()

    Stack.push(result, state)
  end

  defp exec(OpCodes._MUL(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 * op2 &&& AevmConst.mask256()

    Stack.push(result, state)
  end

  defp exec(OpCodes._SUB(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 - op2 &&& AevmConst.mask256()

    Stack.push(result, state)
  end

  defp exec(OpCodes._DIV(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op2 == 0 do
        0
      else
        Integer.floor_div(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._SDIV(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op2 == 0 do
        0
      else
        AevmUtil.sdiv(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._MOD(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op2 == 0 do
        0
      else
        rem(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._SMOD(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op2 == 0 do
        0
      else
        AevmUtil.smod(op1, op2)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._ADDMOD(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)
    {op3, state} = Stack.pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 + op2, op3)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._MULMOD(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)
    {op3, state} = Stack.pop(state)

    result =
      if op3 == 0 do
        0
      else
        rem(op1 * op2, op3)
      end

    masked = result &&& AevmConst.mask256()

    Stack.push(masked, state)
  end

  defp exec(OpCodes._EXP(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = AevmUtil.exp(op1, op2)

    Stack.push(result, state)
  end

  defp exec(OpCodes._SIGNEXTEND(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = AevmUtil.signextend(op1, op2)

    Stack.push(result, state)
  end

  # 10s: Comparison & Bitwise Logic Operations

  defp exec(OpCodes._LT(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op1 < op2 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._GT(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result =
      if op1 > op2 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._SLT(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    sop1 = AevmUtil.signed(op1)
    sop2 = AevmUtil.signed(op2)

    result =
      if sop1 < sop2 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._SGT(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    sop1 = AevmUtil.signed(op1)
    sop2 = AevmUtil.signed(op2)

    result =
      if sop1 > sop2 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._EQ(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    sop1 = AevmUtil.signed(op1)
    sop2 = AevmUtil.signed(op2)

    result =
      if sop1 == sop2 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._ISZERO(), state) do
    {op1, state} = Stack.pop(state)

    result =
      if op1 === 0 do
        1
      else
        0
      end

    Stack.push(result, state)
  end

  defp exec(OpCodes._AND(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 &&& op2

    Stack.push(result, state)
  end

  defp exec(OpCodes._OR(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 ||| op2

    Stack.push(result, state)
  end

  defp exec(OpCodes._XOR(), state) do
    {op1, state} = Stack.pop(state)
    {op2, state} = Stack.pop(state)

    result = op1 ^^^ op2

    Stack.push(result, state)
  end

  defp exec(OpCodes._NOT(), state) do
    {op1, state} = Stack.pop(state)

    result = bnot(op1) &&& AevmConst.mask256()

    Stack.push(result, state)
  end

  defp exec(OpCodes._BYTE(), state) do
    {byte, state} = Stack.pop(state)
    {value, state} = Stack.pop(state)

    result = AevmUtil.byte(byte, value)

    Stack.push(result, state)
  end

  # 20s: SHA3

  defp exec(OpCodes._SHA3(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)

    {value, state3} = Memory.get_area(from_pos, nbytes, state2)
    sha3hash = AevmUtil.sha3_hash(value)
    <<hash::integer-unsigned-256>> = sha3hash
    Stack.push(hash, state3)
  end

  # 30s: Environmental Information

  defp exec(OpCodes._ADDRESS(), state) do
    address = State.address(state)
    Stack.push(address, state)
  end

  defp exec(OpCodes._BALANCE(), state) do
    {address, state} = Stack.pop(state)

    result = State.get_balance(address, state)

    Stack.push(result, state)
  end

  defp exec(OpCodes._ORIGIN(), state) do
    origin = State.origin(state)
    Stack.push(origin, state)
  end

  defp exec(OpCodes._CALLER(), state) do
    caller = State.caller(state)
    Stack.push(caller, state)
  end

  defp exec(OpCodes._CALLVALUE(), state) do
    value = State.value(state)
    Stack.push(value, state)
  end

  defp exec(OpCodes._CALLDATALOAD(), state) do
    {address, state1} = Stack.pop(state)
    value = AevmUtil.value_from_data(address, state1)
    Stack.push(value, state1)
  end

  defp exec(OpCodes._CALLDATASIZE(), state) do
    data = State.data(state)
    value = byte_size(data)
    Stack.push(value, state)
  end

  defp exec(OpCodes._CALLDATACOPY(), state) do
    {nbytes, state1} = Stack.pop(state)
    {from_data_pos, state2} = Stack.pop(state1)
    {to_data_pos, state3} = Stack.pop(state2)

    data = State.data(state)
    data_bytes = AevmUtil.copy_bytes(from_data_pos, to_data_pos, data)
    Memory.write_area(nbytes, data_bytes, state3)
  end

  defp exec(OpCodes._CODESIZE(), state) do
    code = State.code(state)
    value = byte_size(code)
    Stack.push(value, state)
  end

  defp exec(OpCodes._CODECOPY(), state) do
    {nbytes, state1} = Stack.pop(state)
    {from_code_pos, state2} = Stack.pop(state1)
    {to_code_pos, state3} = Stack.pop(state2)

    code = State.code(state)
    code_bytes = AevmUtil.copy_bytes(from_code_pos, to_code_pos, code)
    Memory.write_area(nbytes, code_bytes, state3)
  end

  defp exec(OpCodes._GASPRICE(), state) do
    gas_price = State.gas_price(state)
    Stack.push(gas_price, state)
  end

  defp exec(OpCodes._EXTCODESIZE(), state) do
    {address, state} = Stack.pop(state)

    ext_code_size = State.get_ext_code_size(address, state)

    Stack.push(ext_code_size, state)
  end

  defp exec(OpCodes._EXTCODECOPY(), state) do
    {address, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)
    {from_code_pos, state3} = Stack.pop(state2)
    {to_code_pos, state4} = Stack.pop(state3)

    code = State.get_code(address, state)
    code_bytes = AevmUtil.copy_bytes(from_code_pos, to_code_pos, code)
    Memory.write_area(nbytes, code_bytes, state4)
  end

  defp exec(OpCodes._RETURNDATASIZE(), state) do
    # Not sure what "output data from the previous call from the current env" means
    return_data = State.return_data(state)
    value = byte_size(return_data)
    Stack.push(value, state)
  end

  defp exec(OpCodes._RETURNDATACOPY(), state) do
    {nbytes, state1} = Stack.pop(state)
    {from_rdata_pos, state2} = Stack.pop(state1)
    {to_rdata_pos, state3} = Stack.pop(state2)

    return_data = State.data(state)
    return_data_bytes = AevmUtil.copy_bytes(from_rdata_pos, to_rdata_pos, return_data)
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
    {nth_block, state1} = Stack.pop(state)
    hash = State.calculate_blockhash(nth_block, 0, state1)

    Stack.push(hash, state1)
  end

  defp exec(OpCodes._COINBASE(), state) do
    current_coinbase = State.current_coinbase(state)
    Stack.push(current_coinbase, state)
  end

  defp exec(OpCodes._TIMESTAMP(), state) do
    current_timestamp = State.current_timestamp(state)
    Stack.push(current_timestamp, state)
  end

  defp exec(OpCodes._NUMBER(), state) do
    current_number = State.current_number(state)
    Stack.push(current_number, state)
  end

  defp exec(OpCodes._DIFFICULTY(), state) do
    current_difficulty = State.current_difficulty(state)
    Stack.push(current_difficulty, state)
  end

  defp exec(OpCodes._GASLIMIT(), state) do
    current_gas_limit = State.current_gas_limit(state)
    Stack.push(current_gas_limit, state)
  end

  # 50s: Stack, Memory, Storage and Flow Operations

  defp exec(OpCodes._POP(), state) do
    {_, state} = Stack.pop(state)

    state
  end

  defp exec(OpCodes._MLOAD(), state) do
    {address, state} = Stack.pop(state)

    {result, state1} = Memory.load(address, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._MSTORE(), state) do
    {address, state} = Stack.pop(state)
    {value, state} = Stack.pop(state)

    Memory.store(address, value, state)
  end

  defp exec(OpCodes._MSTORE8(), state) do
    {address, state} = Stack.pop(state)
    {value, state} = Stack.pop(state)

    Memory.store8(address, value, state)
  end

  defp exec(OpCodes._SLOAD(), state) do
    {address, state} = Stack.pop(state)

    result = Storage.sload(address, state)

    Stack.push(result, state)
  end

  defp exec(OpCodes._SSTORE(), state) do
    {key, state} = Stack.pop(state)
    {value, state} = Stack.pop(state)
    Storage.sstore(key, value, state)
  end

  defp exec(OpCodes._JUMP(), state) do
    {position, state} = Stack.pop(state)
    jumpdests = State.jumpdests(state)

    if Enum.member?(jumpdests, position) do
      jumpdest_cost = Gas.op_gas_cost(OpCodes._JUMPDEST())
      state1 = Gas.update_gas(jumpdest_cost, state)
      State.set_pc(position, state1)
    else
      throw({:error, "invalid_jump_dest, #{position}", state})
    end
  end

  defp exec(OpCodes._JUMPI(), state) do
    {position, state} = Stack.pop(state)
    {condition, state} = Stack.pop(state)

    jumpdests = State.jumpdests(state)

    if condition !== 0 do
      if Enum.member?(jumpdests, position) do
        jumpdest_cost = Gas.op_gas_cost(OpCodes._JUMPDEST())
        state1 = Gas.update_gas(jumpdest_cost, state)
        State.set_pc(position, state1)
      else
        throw({:error, "invalid_jump_dest, #{position}", state})
      end
    else
      state
    end
  end

  defp exec(OpCodes._PC(), state) do
    pc = State.pc(state)
    Stack.push(pc, state)
  end

  defp exec(OpCodes._MSIZE(), state) do
    result = Memory.memory_size_bytes(state)

    Stack.push(result, state)
  end

  defp exec(OpCodes._GAS(), state) do
    gas_cost = Gas.op_gas_cost(OpCodes._GAS())
    gas = State.gas(state) - gas_cost
    Stack.push(gas, state)
  end

  defp exec(OpCodes._JUMPDEST(), state) do
    state
  end

  # 60s & 70s: Push Operations

  defp exec(OpCodes._PUSH1() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH2() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH3() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH4() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH5() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH6() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH7() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH8() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH9() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH10() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH11() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH12() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH13() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH14() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH15() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH16() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH17() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH18() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH19() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH20() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH21() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH22() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH23() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH24() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH25() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH26() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH27() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH28() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH29() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH30() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH31() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  defp exec(OpCodes._PUSH32() = current_op, state) do
    bytes = current_op - OpCodes._PUSH1() + 1
    {result, state1} = AevmUtil.move_pc_n_bytes(bytes, state)

    Stack.push(result, state1)
  end

  # 80s: Duplication Operations

  defp exec(OpCodes._DUP1() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP2() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP3() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP4() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP5() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP6() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP7() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP8() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP9() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP10() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP11() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP12() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP13() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP14() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP15() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  defp exec(OpCodes._DUP16() = current_op, state) do
    slot = current_op - OpCodes._DUP1() + 1
    Stack.dup(slot, state)
  end

  # 90s: Exchange Operations

  defp exec(OpCodes._SWAP1() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP2() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP3() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP4() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP5() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP6() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP7() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP8() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP9() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP10() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP11() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP12() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP13() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP14() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP15() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  defp exec(OpCodes._SWAP16() = current_op, state) do
    bytes = current_op - OpCodes._SWAP1() + 1
    Stack.swap(bytes, state)
  end

  # a0s: Logging Operations

  defp exec(OpCodes._LOG0(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)

    AevmUtil.log([], from_pos, nbytes, state2)
  end

  defp exec(OpCodes._LOG1(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)
    {topic1, state3} = Stack.pop(state2)

    AevmUtil.log([topic1], from_pos, nbytes, state3)
  end

  defp exec(OpCodes._LOG2(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)
    {topic1, state3} = Stack.pop(state2)
    {topic2, state4} = Stack.pop(state3)

    AevmUtil.log([topic1, topic2], from_pos, nbytes, state4)
  end

  defp exec(OpCodes._LOG3(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)
    {topic1, state3} = Stack.pop(state2)
    {topic2, state4} = Stack.pop(state3)
    {topic3, state5} = Stack.pop(state4)

    AevmUtil.log([topic1, topic2, topic3], from_pos, nbytes, state5)
  end

  defp exec(OpCodes._LOG4(), state) do
    {from_pos, state1} = Stack.pop(state)
    {nbytes, state2} = Stack.pop(state1)
    {topic1, state3} = Stack.pop(state2)
    {topic2, state4} = Stack.pop(state3)
    {topic3, state5} = Stack.pop(state4)
    {topic4, state6} = Stack.pop(state5)

    AevmUtil.log([topic1, topic2, topic3, topic4], from_pos, nbytes, state6)
  end

  # f0s: System operations

  defp exec(OpCodes._CREATE(), state) do
    {value, state1} = Stack.pop(state)
    {from_pos, state2} = Stack.pop(state1)
    {size, state3} = Stack.pop(state2)

    {area, state4} = Memory.get_area(from_pos, size, state3)
    {account, state5} = AevmUtil.create_account(value, area, state4)

    Stack.push(account, state5)
  end

  defp exec(OpCodes._CALL(), state) do
    {return, state1} = AevmUtil.call(OpCodes._CALL(), state)
    Stack.push(return, state1)
  end

  defp exec(OpCodes._CALLCODE(), state) do
    {return, state1} = AevmUtil.call(OpCodes._CALL(), state)
    Stack.push(return, state1)
  end

  defp exec(OpCodes._RETURN(), state) do
    {from_pos, state} = Stack.pop(state)
    {nbytes, state} = Stack.pop(state)

    {result, state1} = Memory.get_area(from_pos, nbytes, state)

    state2 = State.set_out(result, state1)
    AevmUtil.stop_exec(state2)
  end

  defp exec(OpCodes._DELEGATECALL(), state) do
    {return, state1} = AevmUtil.call(OpCodes._CALL(), state)
    Stack.push(return, state1)
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
    {value, state1} = Stack.pop(state)
    state2 = State.set_selfdestruct(value, state1)

    # mem_gas_cost = Gas.memory_gas_cost(state1, state)
    # State.set_gas()

    AevmUtil.stop_exec(state2)
  end

  defp exec([], state) do
    state
  end
end
