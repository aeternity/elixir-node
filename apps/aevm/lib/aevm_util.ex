defmodule AevmUtil do
  @moduledoc """
  Module containing VM utility functions
  """

  use Bitwise

  require AevmConst
  require OpCodes
  require GasCodes

  @call_depth_limit 1024

  defguardp is_non_neg_integer(value) when is_integer(value) and value >= 0

  @spec default_opts :: map()
  def default_opts do
    %{
      :execute_calls => true
    }
  end

  @doc """
  Stop execution by setting the program counter past the last instruction
  """
  @spec stop_exec(map()) :: map()
  def stop_exec(state) do
    code = State.code(state)
    State.set_pc(byte_size(code), state)
  end

  @doc """
  Perform signed division operation
  """
  def sdiv(_value1, 0), do: 0
  def sdiv(0, -1), do: AevmConst.neg2to255()

  @spec sdiv(integer(), integer()) :: non_neg_integer()
  def sdiv(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    div(svalue1, svalue2) &&& AevmConst.mask256()
  end

  @doc """
  Perform signed modulo operation
  """
  @spec smod(integer(), integer()) :: non_neg_integer()
  def smod(value1, value2) do
    <<svalue1::integer-signed-256>> = <<value1::integer-unsigned-256>>
    <<svalue2::integer-signed-256>> = <<value2::integer-unsigned-256>>
    result = rem(rem(svalue1, svalue2 + svalue2), svalue2)
    result &&& AevmConst.mask256()
  end

  @doc """
  Perform exponential operation
  """
  @spec exp(integer(), integer()) :: integer()
  def exp(op1, op2) do
    pow(op1, op2) &&& AevmConst.mask256()
  end

  @doc """
  Convert unsigned integer to signed integer
  """
  @spec signed(integer()) :: integer()
  def signed(value) do
    <<svalue::integer-signed-256>> = <<value::integer-unsigned-256>>
    svalue
  end

  @doc """
  Extract byte at a given position from a 32-byte integer
  """
  @spec byte(integer(), integer()) :: integer()
  def byte(byte, value) when byte < 32 do
    byte_pos = 256 - 8 * (byte + 1)
    mask = 255
    value >>> byte_pos &&& mask
  end

  def byte(_, _), do: 0

  @doc """
  Get the opcode, corresponding to the value of the program counter
  """
  @spec get_op_code(map()) :: integer()
  def get_op_code(state) do
    pc = State.pc(state)
    code = State.code(state)
    prev_bits = pc * 8

    <<_::size(prev_bits), op_code::size(8), _::binary>> = code

    op_code
  end

  @doc """
  Increase program counter with n `bytes` (instructions)
  """
  @spec move_pc_n_bytes(integer(), map()) :: {integer(), map()}
  def move_pc_n_bytes(bytes, state) do
    old_pc = State.pc(state)
    code = State.code(state)

    curr_pc = old_pc + 1
    prev_bits = curr_pc * 8
    value_size_bits = bytes * 8
    code_byte_size = byte_size(code)

    value =
      cond do
        curr_pc > code_byte_size ->
          0

        curr_pc + bytes >= code_byte_size ->
          extend = (curr_pc + bytes - code_byte_size) * 8
          <<_::size(prev_bits), value::size(value_size_bits)>> = <<code::binary, 0::size(extend)>>
          value

        true ->
          <<_::size(prev_bits), value::size(value_size_bits), _::binary>> = code
          value
      end

    state1 = State.set_pc(old_pc + bytes, state)

    {value, state1}
  end

  def create_account(_value, _area, state) do
    # TODO
    {0xDEADC0DE, state}
  end

  @doc """
  Copy `n` bytes from a given binary, starting at a given byte position
  """
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

  @doc """
  Extract 32-byte integer from the input data, starting at a given `address`
  """
  @spec value_from_data(integer(), map()) :: integer()
  def value_from_data(address, state) do
    data = State.data(state)
    data_copy = copy_bytes(address, 32, data)
    <<value::size(256)>> = data_copy
    value
  end

  @spec sha3_hash(binary()) :: binary()
  def sha3_hash(data) when is_binary(data) do
    hash_bit_length = 256
    :sha3.hash(hash_bit_length, data)
  end

  @doc """
  Load valid jump destinations and store them in the state.
  Requires preprocessing of the code
  (the byte that stands for JUMPDEST shouldn't be
  positioned inside the value of a PUSHn instruction)
  """
  def load_jumpdests(%{pc: pc, code: code} = state) when pc >= byte_size(code) do
    State.set_pc(0, state)
  end

  def load_jumpdests(state) do
    pc = State.pc(state)

    op_code = get_op_code(state)

    loaded_jumpdests_state =
      cond do
        op_code == OpCodes._JUMPDEST() ->
          jumpdests = State.jumpdests(state)
          %{state | jumpdests: [pc | jumpdests]}

        op_code >= OpCodes._PUSH1() && op_code <= OpCodes._PUSH32() ->
          bytes = op_code - OpCodes._PUSH1() + 1
          {_, moved_pc_state} = move_pc_n_bytes(bytes, state)
          moved_pc_state

        true ->
          state
      end

    updated_pc_state = State.inc_pc(loaded_jumpdests_state)
    load_jumpdests(updated_pc_state)
  end

  @doc """
  Generate a log entry with given `topics`, together with extracted area
  from the memory, by given position and number of bytes,
  and add it to the state
  """
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

  @doc """
  Perform a sign extension operation
  """
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

  @doc """
  Execute a CALL instruction
  """
  @spec call(integer(), map()) :: {integer(), map()}
  def call(op_code, state) do
    if State.calldepth(state) < @call_depth_limit do
      execute_call(op_code, state)
    else
      {0, state}
    end
  end

  defp pow(op1, op2) when is_non_neg_integer(op1) and is_non_neg_integer(op2),
    do: pow(1, op1, op2)

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

  # Perform a CALL instruction.
  # Determines the needed data for the execution, based on the `op_code` provided,
  # then makes a new instance of the VM with this data, and a fresh copy of
  # memory and stack, but with the same storage.
  #
  # Returns a tuple, containing the result from the CALL instruction
  # and the upgraded outer `state`

  defp execute_call(op_code, state) do
    {gas, to, value, input_offset, input_size, output_offset, output_size,
     state_popped_call_params} = get_call_params(op_code, state)

    spent_call_gas_state = spend_call_gas(state_popped_call_params, state)

    {input_area, updated_memory_size_state} =
      Memory.get_area(input_offset, input_size, spent_call_gas_state)

    call_gas = adjust_call_gas(gas, value)
    caller = determine_call_caller(op_code, updated_memory_size_state)
    dest = determine_call_dest(op_code, state)

    call_state =
      State.init_for_call(
        call_gas,
        to,
        value,
        input_area,
        caller,
        dest,
        updated_memory_size_state,
        %{
          default_opts()
          | :execute_calls => State.execute_calls(updated_memory_size_state)
        }
      )

    if State.execute_calls(call_state) do
      {ret, out_gas} =
        try do
          {:ok, out_state} = Aevm.loop(call_state)
          {1, State.gas(out_state)}
        catch
          {:error, _, _} ->
            {0, 0}
        end

      remaining_gas = State.gas(updated_memory_size_state) + out_gas
      updated_gas_state = State.set_gas(remaining_gas, updated_memory_size_state)

      added_callcreate_state =
        State.add_callcreate(input_area, dest, call_gas, value, updated_gas_state)

      final_state =
        case ret do
          1 ->
            {message, _} = Memory.get_area(0, output_size, added_callcreate_state)

            updated_memory_size_state =
              Memory.write_area(output_offset, message, added_callcreate_state)

            mem_gas_cost = Gas.memory_gas_cost(updated_memory_size_state, added_callcreate_state)
            State.set_gas(remaining_gas - mem_gas_cost, updated_memory_size_state)

          0 ->
            added_callcreate_state
        end

      {ret, final_state}
    else
      remaining_gas = State.gas(updated_memory_size_state) + call_gas
      updated_memory_size_state = State.set_gas(remaining_gas, updated_memory_size_state)

      added_callcreate_state =
        State.add_callcreate(input_area, dest, call_gas, value, updated_memory_size_state)

      {1, added_callcreate_state}
    end
  end

  # Extract the needed call parameters from the `state`, based on the given `op_code`

  defp get_call_params(op_code, state) do
    {gas, state_popped_gas} = Stack.pop(state)
    {to, state_popped_to} = Stack.pop(state_popped_gas)
    {value, state_popped_value} = determine_call_value(op_code, state_popped_to)
    {input_offset, state_popped_input_offset} = Stack.pop(state_popped_value)
    {input_size, state_popped_input_size} = Stack.pop(state_popped_input_offset)
    {output_offset, state_popped_output_offset} = Stack.pop(state_popped_input_size)
    {output_size, state_popped_output_size} = Stack.pop(state_popped_output_offset)

    {gas, to, value, input_offset, input_size, output_offset, output_size,
     state_popped_output_size}
  end

  defp spend_call_gas(current_state, initial_state) do
    op_code = get_op_code(initial_state)
    op_name = OpCodesUtil.mnemonic(op_code)

    dynamic_gas_cost = Gas.dynamic_gas_cost(op_name, initial_state)
    mem_gas_cost = Gas.memory_gas_cost(current_state, initial_state)
    op_gas_cost = Gas.op_gas_cost(op_code)

    gas_cost = mem_gas_cost + dynamic_gas_cost + op_gas_cost

    Gas.update_gas(gas_cost, current_state)
  end

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

  # Adjust the `gas`, provided for the inner CALL instruction

  defp adjust_call_gas(gas, value) do
    if value != 0 do
      gas + GasCodes._GCALLSTIPEND()
    else
      gas
    end
  end
end
