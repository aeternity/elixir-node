defmodule Aernold do

  defp reduce_to_value({:int, int}, _state) do
    int
  end

  defp reduce_to_value({:bool, bool}, state) do
    bool
  end

  defp reduce_to_value({:hex, hex}, state) do
    to_string(hex)
  end

  defp reduce_to_value({:char, char}, state) do
    char
  end

  defp reduce_to_value({:string, string}, state) do
    string
  end

  defp reduce_to_value({:id, id}, state) do
    id
  end

  defp reduce_to_value({:type, type}, state) do
    type
  end

  defp reduce_to_value({{op, _}, lhs, rhs}, state) do
    cond do
      op == "=" ->
        IO.inspect("Assign")
        lhs = reduce_to_value(lhs, state)
        rhs = reduce_to_value(rhs, state)
        Map.merge(state, %{lhs => rhs})
      op == "+" ->
        IO.inspect("ADD")
        reduce_to_value(lhs, state) + reduce_to_value(rhs, state)
      op == "-" ->
        IO.inspect("SUB")
        reduce_to_value(lhs, state) - reduce_to_value(rhs, state)
      op == "*" ->
        IO.inspect("MUL")
        reduce_to_value(lhs, state) * reduce_to_value(rhs, state)
      op == "/" ->
        IO.inspect("DIV")
        reduce_to_value(lhs, state) / reduce_to_value(rhs, state)
    end
  end

  defp evaluate_ast([{lhs, _}, rhs | tail], state) do
    IO.puts "-----------------LHS------------------"
    IO.inspect(lhs)
    IO.puts "-----------------RHS----------------"
    IO.inspect(rhs)
    IO.puts "..................TAIL..................."
    IO.inspect(tail)
    rhs_value = reduce_to_value(rhs, state)
    evaluate_ast(tail, Map.merge(state, %{lhs => rhs_value}))
  end

  defp evaluate_ast([{op, lhs, rhs} | tail], state) do
    IO.puts "-----------------LHS------------------"
    IO.inspect(lhs)
    IO.puts "-----------------RHS----------------"
    IO.inspect(rhs)
    IO.puts "..................TAIL..................."
    IO.inspect(tail)
    lhs_value = reduce_to_value(lhs, state)
    IO.inspect(lhs_value)
    rhs_value = reduce_to_value(rhs, state)
    IO.inspect(rhs_value)
    evaluate_ast(tail, Map.merge(state, %{lhs_value => rhs_value}))
  end

  defp evaluate_ast([{:def_var, id, type, value} | tail], state) do
    hex_regex = ~r{0[xX][0-9a-fA-F]+}
    extracted_id = reduce_to_value(id, state)
    IO.inspect("Extracted id = #{extracted_id}")
    extracted_type = reduce_to_value(type, state)
    IO.inspect("Extracted type = #{extracted_type}")
    extracted_value = reduce_to_value(value, state)
    IO.inspect("Extracted value = #{extracted_value}")
    cond do
      extracted_type == 'Int' && !(is_integer(extracted_value)) ->
        throw({:error, "The value of (#{extracted_id}) must be Integer"})
      extracted_type == 'Bool' && !(is_boolean(extracted_value)) ->
        throw({:error, "The value of (#{extracted_id}) must be Boolean"})
      extracted_type == 'String' && !(String.valid?(extracted_value)) ->
        throw({:error, "The value of (#{extracted_id}) must be String"})
      extracted_type == 'Hex' &&  !(extracted_value =~ hex_regex) ->
        throw({:error, "The value of (#{extracted_id}) must be Hex"})
      extracted_type == 'Char' && !(is_list(extracted_value)) ->
        throw({:error, "The value of (#{extracted_id}) must be Char"})
      true ->
        evaluate_ast(tail, Map.merge(state, %{extracted_id => {extracted_type, extracted_value}}))
    end
  end

  defp evaluate_ast([], state) do
    state
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
    with {:ok, tokens, _} <- :aernold_lexer.string(to_char_list(content)),
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
