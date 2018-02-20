defmodule ASTNodeUtils do

  def validate_variable_value!(id, type, value, _scope) do
    hex_regex = ~r{[0-9a-fA-F]+}
    cond do
      type == 'Int' && !(is_integer(value)) ->
        throw({:error, "The value of (#{id}) must be Integer"})
      type == 'Bool' && !(is_boolean(value)) ->
        throw({:error, "The value of (#{id}) must be Boolean"})
      type == 'String' && !(String.valid?(value)) ->
        throw({:error, "The value of (#{id}) must be String"})
      type == 'Hex' &&  !(value =~ hex_regex) ->
        throw({:error, "The value of (#{id}) must be Hex"})
      type == 'Char' && !(String.valid?(value)) ->
        throw({:error, "The value of (#{id}) must be Char"})
      true ->
        :ok
    end
  end

  def update_scope(old_scope, new_scope) do
    Enum.reduce(new_scope, old_scope, fn({var_id, var_value}, scope_acc) ->
      if Map.has_key?(scope_acc, var_id) do
        Map.replace!(scope_acc, var_id,  var_value)
      else
        scope_acc
      end
    end)
  end

  ##This is from elixir v1.6, the following will be removed
  ##once the project migrates to v1.6
  def ascii_printable?(list, counter \\ :infinity)

  def ascii_printable?(_, 0) do
    true
  end

  def ascii_printable?([char | rest], counter)
      when is_integer(char) and char >= 32 and char <= 126 do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\n | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\r | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\t | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\v | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\b | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\f | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\e | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([?\a | rest], counter) do
    ascii_printable?(rest, decrement(counter))
  end

  def ascii_printable?([], _counter), do: true
  def ascii_printable?(_, _counter), do: false

  @compile {:inline, decrement: 1}
  defp decrement(:infinity), do: :infinity
  defp decrement(counter), do: counter - 1

end
