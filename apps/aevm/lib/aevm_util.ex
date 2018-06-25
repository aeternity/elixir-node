defmodule AevmUtil do
  @moduledoc """
    Module containing all the VM utility functions
  """

  use Bitwise

  require AevmConst
  require OpCodes
  require GasCodes

  def default_opts do
    %{
      :execute_calls => true
    }
  end

  def stop_exec(state) do
    code = State.code(state)
    State.set_cp(byte_size(code), state)
  end

  def sdiv(_value1, 0), do: 0
  def sdiv(0, -1), do: AevmConst.neg2to255()

  def sdiv(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    div(svalue1, svalue2) &&& AevmConst.mask256()
  end

  def smod(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    result = rem(rem(svalue1, svalue2 + svalue2), svalue2)
    result &&& AevmConst.mask256()
  end

  def pow(op1, op2) when is_integer(op1) and is_integer(op2) and op2 >= 0, do: pow(1, op1, op2)

  def pow(n, _, 0), do: n
  def pow(n, op1, 1), do: op1 * n

  def pow(n, op1, op2) do
    square = op1 * op1 &&& AevmConst.mask256()
    exp = op2 >>> 1

    case op2 &&& 1 do
      0 -> pow(n, square, exp)
      _ -> pow(op1 * n, square, exp)
    end
  end

  def exp(op1, op2) do
    pow(op1, op2) &&& AevmConst.mask256()
  end

  def signed(value) do
    <<svalue::integer-signed-256>> = <<value::integer-unsigned-256>>
    svalue
  end

  def byte(byte, value) when byte < 32 do
    byte_pos = 256 - 8 * (byte + 1)
    mask = 255
    value >>> byte_pos &&& mask
  end

  def byte(_, _), do: 0

  def push(value, state) do
    Stack.push(value, state)
  end

  def pop(state) do
    Stack.pop(state)
  end

  def dup(index, state) do
    Stack.dup(index, state)
  end

  def swap(index, state) do
    Stack.swap(index, state)
  end

  def get_op_code(state) do
    cp = State.cp(state)
    code = State.code(state)
    prev_bits = cp * 8

    <<_::size(prev_bits), op_code::size(8), _::binary>> = code

    op_code
  end

  def move_cp_n_bytes(bytes, state) do
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

  def create_account(_value, _area, state) do
    # TODO
    {0xDEADC0DE, state}
  end

  def copy_bytes(from_byte, n, bin_data) do
    size = byte_size(bin_data)
    bit_pos = from_byte * 8

    cond do
      from_byte + n >= size && from_byte > size ->
        byte_size = n * 8
        <<0::size(byte_size)>>

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

  def value_from_data(address, state) do
    data = State.data(state)
    data_copy = copy_bytes(address, 32, data)
    <<value::size(256)>> = data_copy
    value
  end

  def sha3_hash(data) when is_binary(data) do
    :sha3.hash(256, data)
  end

  def load_jumpdests(%{cp: cp, code: code} = state) when cp >= byte_size(code) do
    State.set_cp(0, state)
  end

  def load_jumpdests(state) do
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

  def log(topics, from_pos, nbytes, state) do
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

  def signextend(op1, op2) do
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

  def call(state, op_code) do
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
            {:ok, out_state} = Aevm.loop(call_state)
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

end
