defmodule Aernold do

  def parse(filename) do
    {:ok, file} = File.read(filename)
    with {:ok, tokens, _} <- :aernold_lexer.string(to_char_list(file)),
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
