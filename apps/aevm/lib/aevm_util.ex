defmodule AevmUtil do
  @moduledoc """
    Module containing all the VM utility functions
  """

  use Bitwise

  require AevmConst
  require OpCodes
  require GasCodes

  @spec default_opts :: map()
  def default_opts do
    %{
      :execute_calls => true
    }
  end

  @spec stop_exec(map()) :: map()
  def stop_exec(state) do
    code = State.code(state)
    State.set_cp(byte_size(code), state)
  end

  def sdiv(_value1, 0), do: 0
  def sdiv(0, -1), do: AevmConst.neg2to255()

  @spec sdiv(integer(), integer()) :: non_neg_integer()
  def sdiv(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    div(svalue1, svalue2) &&& AevmConst.mask256()
  end

  @spec smod(integer(), integer()) :: non_neg_integer()
  def smod(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    result = rem(rem(svalue1, svalue2 + svalue2), svalue2)
    result &&& AevmConst.mask256()
  end

  def pow(op1, op2) when is_integer(op1) and is_integer(op2) and op2 >= 0, do: pow(1, op1, op2)

  def pow(n, _, 0), do: n
  def pow(n, op1, 1), do: op1 * n

  @spec pow(integer(), integer(), integer()) :: integer()
  def pow(n, op1, op2) do
    square = op1 * op1 &&& AevmConst.mask256()
    exp = op2 >>> 1

    case op2 &&& 1 do
      0 -> pow(n, square, exp)
      _ -> pow(op1 * n, square, exp)
    end
  end

  @spec exp(integer(), integer()) :: integer()
  def exp(op1, op2) do
    pow(op1, op2) &&& AevmConst.mask256()
  end

  @spec signed(integer()) :: integer()
  def signed(value) do
    <<svalue::integer-signed-256>> = <<value::integer-unsigned-256>>
    svalue
  end

  @spec byte(integer(), integer()) :: integer()
  def byte(byte, value) when byte < 32 do
    byte_pos = 256 - 8 * (byte + 1)
    mask = 255
    value >>> byte_pos &&& mask
  end

  def byte(_, _), do: 0

  @spec get_op_code(map()) :: integer()
  def get_op_code(state) do
    cp = State.cp(state)
    code = State.code(state)
    prev_bits = cp * 8

    <<_::size(prev_bits), op_code::size(8), _::binary>> = code

    op_code
  end

  @spec move_cp_n_bytes(integer(), map()) :: {integer(), map()}
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

  @spec copy_bytes(integer(), integer(), binary()) :: binary()
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

  @spec value_from_data(integer(), map()) :: integer()
  def value_from_data(address, state) do
    data = State.data(state)
    data_copy = copy_bytes(address, 32, data)
    <<value::size(256)>> = data_copy
    value
  end

  @spec sha3_hash(binary()) :: binary()
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

  @spec log(list(), integer(), integer(), map()) :: map()
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

  @spec signextend(integer(), integer()) :: integer()
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

  @spec call(integer(), map()) :: {integer(), map()}
  def call(op_code, state) do
    if State.calldepth(state) < 1024 do
      call1(op_code, state)
    else
      {0, state}
    end
  end

  @spec call1(integer(), map()) :: {integer(), map()}
  defp call1(op_code, state) do
    {gas, state1} = Stack.pop(state)
    {to, state2} = Stack.pop(state1)
    {value, state3} = determine_call_value(op_code, state2)
    {in_offset, state4} = Stack.pop(state3)
    {in_size, state5} = Stack.pop(state4)
    {out_offset, state6} = Stack.pop(state5)
    {out_size, state7} = Stack.pop(state6)

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
    caller = determine_call_caller(op_code, state9)
    dest = determine_call_dest(op_code, state)

    call_state =
      State.init_for_call(call_gas, to, value, in_area, caller, dest, state9, %{
        default_opts()
        | :execute_calls => State.execute_calls(state9)
      })

    if State.execute_calls(call_state) do
      {ret, out_gas} =
        try do
          {:ok, out_state} = Aevm.loop(call_state)
          {1, State.gas(out_state)}
        catch
          {:error, _, _} ->
            {0, 0}
        end

      remaining_gas = State.gas(state9) + out_gas
      return_state1 = State.set_gas(remaining_gas, state9)
      return_state2 = State.add_callcreate(in_area, dest, call_gas, value, return_state1)

      final_return_state =
        case ret do
          1 ->
            {message, _} = Memory.get_area(0, out_size, return_state2)
            return_state3 = Memory.write_area(out_offset, message, return_state2)
            mem_gas_cost = Gas.memory_gas_cost(return_state3, return_state2)
            State.set_gas(remaining_gas - mem_gas_cost, return_state3)

          0 ->
            return_state2
        end

      {ret, final_return_state}
    else
      remaining_gas = State.gas(state9) + call_gas
      state10 = State.set_gas(remaining_gas, state9)
      state11 = State.add_callcreate(in_area, dest, call_gas, value, state10)

      {1, state11}
    end
  end

  @spec determine_call_value(integer(), map()) :: any()
  defp determine_call_value(op_code, state) do
    case op_code do
      OpCodes._CALL() ->
        Stack.pop(state)

      OpCodes._CALLCODE() ->
        Stack.pop(state)

      OpCodes._DELEGATECALL() ->
        {State.value(state), state}
    end
  end

  @spec determine_call_caller(integer(), map) :: any()
  defp determine_call_caller(op_code, state) do
    case op_code do
      OpCodes._CALL() ->
        State.address(state)

      OpCodes._CALLCODE() ->
        State.address(state)

      OpCodes._DELEGATECALL() ->
        State.caller(state)
    end
  end

  @spec determine_call_caller(integer(), map()) :: any()
  defp determine_call_dest(op_code, state) do
    case op_code do
      OpCodes._CALL() ->
        Stack.peek(1, state)

      OpCodes._CALLCODE() ->
        State.address(state)

      OpCodes._DELEGATECALL() ->
        State.address(state)
    end
  end

  @spec adjust_call_gas(integer(), integer()) :: integer()
  defp adjust_call_gas(gas, value) do
    if value != 0 do
      gas + GasCodes._GCALLSTIPEND()
    else
      gas
    end
  end
end
