defmodule ASTNodeUtils do

  def validate_variable_value!(id, type, value, scope) do
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

end
