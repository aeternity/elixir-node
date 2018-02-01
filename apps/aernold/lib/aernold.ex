defmodule Aernold do

  defp reduce_to_value({:int, int}, _scope) do
    if !(is_integer(int)) do
      throw({:error, "The value must be Integer"})
    else
      int
    end
  end

  defp reduce_to_value('Int', _scope) do
    0
  end

  defp reduce_to_value({:bool, bool}, _scope) do
    if !(is_boolean(bool)) do
      throw({:error, "The value must be Boolean"})
    else
      bool
    end
  end

  defp reduce_to_value('Bool', _scope) do
    false
  end

  defp reduce_to_value({:hex, hex}, _scope) do
    hex_regex = ~r{0[xX][0-9a-fA-F]+}
    hex = to_string(hex)
    if !(hex =~ hex_regex) do
      throw({:error, "The value must be Hex"})
    else
      hex
    end
  end

  defp reduce_to_value('Hex', _scope) do
    0x0
  end

  defp reduce_to_value({:char, char}, _scope) do
    if !(is_list(char)) do
      throw({:error, "The value must be Char"})
    else
      char
    end
  end

  defp reduce_to_value('Char', _scope) do
    ''
  end

  defp reduce_to_value({:string, string}, _scope) do
    if !(String.valid?(string)) do
      throw({:error, "The value must be String"})
    else
      string
    end
  end

  defp reduce_to_value('String', _scope) do
    ""
  end

  defp reduce_to_value({:id, id}, scope) do
    if !Map.has_key?(scope, id) do
      throw({:error, "Undefined variable (#{id})"})
    end

    %{value: value} = Map.get(scope, id)
    value
  end

  defp reduce_to_value({:type, type}, _scope) do
    type
  end

  ## Arithmetic operations
  ## TODO: arithemetic operations priority
  defp reduce_to_value({lhs, {:+, _}, rhs}, scope) do
    result = reduce_to_value(lhs, scope) + reduce_to_value(rhs, scope)
  end

  defp reduce_to_value({lhs, {:-, _}, rhs}, scope) do
    result = reduce_to_value(lhs, scope) - reduce_to_value(rhs, scope)
  end

  defp reduce_to_value({lhs, {:*, _}, rhs}, scope) do
    result = reduce_to_value(lhs, scope) * reduce_to_value(rhs, scope)
  end

  defp reduce_to_value({lhs, {:/, _}, rhs}, scope) do
    result = Integer.floor_div(reduce_to_value(lhs, scope), reduce_to_value(rhs, scope))
  end

  ## Equality Operators
  defp reduce_to_value({lhs, {:==, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value == rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:!=, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value != rhs_value, do: true, else: false
  end

  ## Relational operators
  ## TODO: discuss if we want to have these outside of if
  defp reduce_to_value({lhs, {:>, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value > rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:>=, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value >= rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:<, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value < rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:<=, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value <= rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:&&, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value && rhs_value, do: true, else: false
  end

  defp reduce_to_value({lhs, {:||, _}, rhs}, scope) do
    lhs_value = reduce_to_value(lhs, scope)
    rhs_value = reduce_to_value(rhs, scope)

    if lhs_value || rhs_value, do: true, else: false
  end

  defp validate_variable_value!(id, type, value, scope) do
    hex_regex = ~r{0[xX][0-9a-fA-F]+}
    cond do
      type == 'Int' && !(is_integer(value)) ->
        throw({:error, "The value of (#{id}) must be Integer"})
      type == 'Bool' && !(is_boolean(value)) ->
        throw({:error, "The value of (#{id}) must be Boolean"})
      type == 'String' && !(String.valid?(value)) ->
        throw({:error, "The value of (#{id}) must be String"})
      type == 'Hex' &&  !(value =~ hex_regex) ->
        throw({:error, "The value of (#{id}) must be Hex"})
      type == 'Char' && !(is_list(value)) ->
        throw({:error, "The value of (#{id}) must be Char"})
      true ->
        :ok
    end
  end

  defp evaluate_ast({{:contract, _}, _id, body}, scope) do
    Enum.reduce(body, scope, fn(statement, scope_acc) ->
      evaluate_ast(statement, scope_acc)
    end)
  end

  defp evaluate_ast({:decl_var, {_, id}, {_, type}}, scope) do
    default_value = reduce_to_value(type, scope)
    Map.put(scope, id, %{type: type, value: default_value})
  end

  defp evaluate_ast({:def_var, {_, id}, {_, type}, value}, scope) do
    extracted_value = reduce_to_value(value, scope)
    validate_variable_value!(id, type, extracted_value, scope)

    Map.put(scope, id, %{type: type, value: extracted_value})
  end

  defp evaluate_ast({{:id, id}, {:=, _}, value}, scope) do
    extracted_value = reduce_to_value(value, scope)
    %{type: type} = Map.get(scope, id)

    validate_variable_value!(id, type, extracted_value, scope)

    Map.put(scope, id, %{type: type, value: extracted_value})
  end

  defp evaluate_ast({:if_statement, condition, body}, scope) do
    condition_result = reduce_to_value(condition, scope)
    if condition_result do
      Enum.reduce(body, scope, fn(statement, scope_acc) ->
        evaluate_ast(statement, scope_acc)
      end)
    else
      scope
    end

    # TODO: make each scope independent
    # scope
  end

  defp evaluate_ast({}, scope) do
    scope
  end

  def process_ast(ast) do
    evaluate_ast(ast, %{})
  end

  def parse_string(string) do
    parse(string)
  end

  def parse_file(filename) do
    file = Path.absname("apps/aernold/" <> filename)
    {:ok, file_content} = File.read(file)
    parse(file_content)
  end

  defp parse(content) do
    with {:ok, tokens, _} <- :aernold_lexer.string(to_charlist(content)),
         {:ok, result} <- :aernold_parser.parse(tokens)
    do
      process_ast(result)
    else
      {:error, reason, _} ->
        reason
      {:error, {_, :aernold_lexer, reason}} ->
        to_string(reason)
    end
  end
end
