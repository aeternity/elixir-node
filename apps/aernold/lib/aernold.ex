defmodule Aernold do

  def parse(filename) do
    file = Path.absname("apps/aernold/" <> filename)
    {:ok, file_content} = File.read(file)
    with {:ok, tokens, _} <- :aernold_lexer.string(to_char_list(file_content)),
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
