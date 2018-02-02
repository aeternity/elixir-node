defmodule Aernold do

  def process_ast(ast) do
    ASTNode.evaluate(ast, {nil, %{}})
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
