defmodule Reducer do

  def to_value({:int, int}, {_, _scope}) do
    if !(is_integer(int)) do
      throw({:error, "The value must be Integer"})
    else
      int
    end
  end

  def to_value('Int', {_, _scope}) do
    0
  end

  def to_value({:bool, bool}, {_, _scope}) do
    if !(is_boolean(bool)) do
      throw({:error, "The value must be Boolean"})
    else
      bool
    end
  end

  def to_value('Bool', {_, _scope}) do
    false
  end

  def to_value({:hex, hex}, {_, _scope}) do
    hex_regex = ~r{0[xX][0-9a-fA-F]+}
    hex = to_string(hex)
    if !(hex =~ hex_regex) do
      throw({:error, "The value must be Hex"})
    else
      hex
    end
  end

  def to_value('Hex', {_, _scope}) do
    0x0
  end

  def to_value({:char, char}, {_, _scope}) do
    if !(is_list(char)) do
      throw({:error, "The value must be Char"})
    else
      char
    end
  end

  def to_value('Char', {_, _scope}) do
    ''
  end

  def to_value({:string, string}, {_, _scope}) do
    if !(String.valid?(string)) do
      throw({:error, "The value must be String"})
    else
      string
    end
  end

  def to_value('String', {_, _scope}) do
    ""
  end

  def to_value({:id, id}, {_, scope}) do
    if !Map.has_key?(scope, id) do
      throw({:error, "Undefined variable (#{id})"})
    end

    %{value: value} = Map.get(scope, id)
    value
  end

  def to_value({:type, type}, _scope) do
    type
  end

  ## Arithmetic operations
  ## TODO: arithemetic operations priority
  def to_value({lhs, {:+, _}, rhs}, {prev_val, scope}) do
    to_value(lhs, {prev_val, scope}) + to_value(rhs, {prev_val, scope})
  end

  def to_value({lhs, {:-, _}, rhs}, {prev_val, scope}) do
    to_value(lhs, {prev_val, scope}) - to_value(rhs, {prev_val, scope})
  end

  def to_value({lhs, {:*, _}, rhs}, {prev_val, scope}) do
    to_value(lhs, {prev_val, scope}) * to_value(rhs, {prev_val, scope})
  end

  def to_value({lhs, {:/, _}, rhs}, {prev_val, scope}) do
    Integer.floor_div(to_value(lhs, {prev_val, scope}), to_value(rhs, {prev_val, scope}))
  end

  ## Equality Operators
  def to_value({lhs, {:==, _}, rhs}, {_prev_val, scope}) do
    lhs_value = to_value(lhs, {nil, scope})
    rhs_value = to_value(rhs, {nil, scope})

    if lhs_value == rhs_value, do: true, else: false
  end

  def to_value({lhs, {:!=, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value != rhs_value, do: true, else: false
  end

  ## Relational operators
  ## TODO: discuss if we want to have these outside of if
  def to_value({lhs, {:>, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value > rhs_value, do: true, else: false
  end

  def to_value({lhs, {:>=, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value >= rhs_value, do: true, else: false
  end

  def to_value({lhs, {:<, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value < rhs_value, do: true, else: false
  end

  def to_value({lhs, {:<=, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value <= rhs_value, do: true, else: false
  end

  def to_value({lhs, {:&&, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value && rhs_value, do: true, else: false
  end

  def to_value({lhs, {:||, _}, rhs}, {prev_val, scope}) do
    lhs_value = to_value(lhs, {prev_val, scope})
    rhs_value = to_value(rhs, {prev_val, scope})

    if lhs_value || rhs_value, do: true, else: false
  end

  def to_value({:func_call, {_, id}, args}, {_prev_val, scope}) do
    {_, {_, _, params, body} = func} = Enum.find(scope, fn(s) ->
      scope_val = elem(s, 1)
      if !is_map(scope_val) do
        elem(scope_val, 0) == :func_definition
      else
        false
      end
    end)

    {_, scope} = Enum.reduce(params, {0, scope}, fn(param, {args_index, scope_acc}) ->
      arg = elem(args, args_index)
      {_, id, type} = param
      var_def = {:def_var, id, type, arg}

      {_, scope_acc} = ASTNode.evaluate(var_def, {nil, scope_acc})
      {args_index + 1, scope_acc}
    end)

    {return_val, scope} = Enum.reduce(body, {nil, scope}, fn(statement, {prev_val, scope_acc}) ->
      ASTNode.evaluate(statement, {prev_val, scope_acc})
    end)

    return_val
  end

end
