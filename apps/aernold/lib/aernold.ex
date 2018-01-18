defmodule Aernold do

  defp reduce_to_value({:int, _line, value}, _state) do

  end

  defp reduce_to_value({:string, _line, string}, state) do

  end

  defp reduce_to_value({:char, _line, char}, state) do

  end

  defp reduce_to_value({:hex, _line, hex}, state) do

  end

  defp reduce_to_value({:add_op, lhs, rhs}, state) do
    #reduce_to_value(lhs, state) + reduce_to_value(rhs, state)
  end

  defp reduce_to_value({:sub_op, lhs, rhs}, state) do
    #reduce_to_value(lhs, state) - reduce_to_value(rhs, state)
  end

  defp reduce_to_value({:mul_op, lhs, rhs}, state) do
    #reduce_to_value(lhs, state) * reduce_to_value(rhs, state)
  end

  defp reduce_to_value({:div_op, lhs, rhs}, state) do
    #reduce_to_value(lhs, state) / reduce_to_value(rhs, state)
  end

  def eval([], state) do
    #state
  end

  def process_ast(ast) do
    #eval(tree, %{})
  end

  def parse_string(string) do
    #parse(string)
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
      result
    else
      {:error, reason, _} ->
        reason
      {:error, {_, :aernold_lexer, reason}} ->
        to_string(reason)
    end
  end
end
