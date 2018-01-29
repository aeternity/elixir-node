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
    [char]
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

  defp reduce_to_value({lhs, {op, _}, rhs}, state) do
    op = to_string(op)
    cond do
      op == "+" ->
        reduce_to_value(lhs, state) + reduce_to_value(rhs, state)
      op == "-" ->
        reduce_to_value(lhs, state) - reduce_to_value(rhs, state)
      op == "*" ->
        reduce_to_value(lhs, state) * reduce_to_value(rhs, state)
      op == "/" ->
        reduce_to_value(lhs, state) / reduce_to_value(rhs, state)
      op == "==" ->
        #just for testing
        state =  Map.put(state, 'a', 5)
        state = Map.put(state, 'b', 5)
        lhs = reduce_to_value(lhs, state)
        rhs = reduce_to_value(rhs, state)
        if Map.has_key?(state, lhs) && Map.has_key?(state, rhs) do
          lhs_value = Map.get(state, lhs)
          rhs_value = Map.get(state, rhs)
          if lhs_value == rhs_value, do: :true, else: :false
        end
    end
  end

  defp evaluate_ast([{:contract, _}, rhs | tail], state) do
    IO.puts "1-----------------RHS----------------1"
    IO.inspect(rhs)
    IO.puts "1..................TAIL...................1"
    IO.inspect(tail)
    rhs_value = reduce_to_value(rhs, state)
    IO.puts "1----------------reduced RHS --------------1"
    IO.inspect(rhs_value)
    evaluate_ast(tail, Map.merge(state, %{:contract => rhs_value}))
  end

  defp evaluate_ast([{lhs, op, rhs} | tail], state) do
    IO.puts "2-----------------LHS------------------2"
    IO.inspect(lhs)
    IO.puts "2-----------------RHS----------------2"
    IO.inspect(rhs)
    IO.puts "2..................TAIL...................2"
    IO.inspect(tail)
    lhs_value = reduce_to_value(lhs, state)
    IO.puts "2-----------------reduced LHS side-------------2"
    IO.inspect(lhs_value)
    rhs_value = reduce_to_value(rhs, state)
    IO.puts "2-----------------reduced RHS side-------------2"
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
  #it doesnt work correctly right now
  defp evaluate_ast([{:if_statement, condition, body} | tail], state) do
    extracted_condition = reduce_to_value(condition, state)
    IO.inspect(extracted_condition)
    extracted_body = reduce_to_value(body, state)
    IO.inspect(extracted_body)
    if extracted_condition do
      evaluate_ast(tail, Map.merge(state, %{"if"=> "works"}))
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
