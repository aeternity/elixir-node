defmodule ASTNodeUtils do
  def validate_variable_value!(id, type, value, _scope) do
    hex_regex = ~r{[0-9a-fA-F]+}

    cond do
      type == 'Int' && !is_integer(value) ->
        throw({:error, "The value of (#{id}) must be Integer"})

      type == 'Bool' && !is_boolean(value) ->
        throw({:error, "The value of (#{id}) must be Boolean"})

      type == 'String' && !String.valid?(value) ->
        throw({:error, "The value of (#{id}) must be String"})

      type == 'Hex' && !(value =~ hex_regex) ->
        throw({:error, "The value of (#{id}) must be Hex"})

      type == 'Char' && !String.valid?(value) ->
        throw({:error, "The value of (#{id}) must be Char"})

      true ->
        :ok
    end
  end

  def update_scope(old_scope, new_scope) do
    Enum.reduce(new_scope, old_scope, fn {var_id, var_value}, scope_acc ->
      if Map.has_key?(scope_acc, var_id) do
        Map.replace!(scope_acc, var_id, var_value)
      else
        scope_acc
      end
    end)
  end

  ## This is going to be optimised (probably with spawn for each cond)
  def check_list_item_type(list) do
    cond do
      Enum.all?(list, fn x -> is_integer(x) end) != true ->
        throw({:error, "Lists must be homogeneous"})

      Enum.all?(list, fn x -> is_bitstring(x) end) != false ->
        throw({:error, "Lists must be homogeneous"})

      Enum.all?(list, fn x -> is_list(x) end) != false ->
        throw({:error, "Lists must be homogeneous"})

      Enum.all?(list, fn x -> is_boolean(x) end) != false ->
        throw({:error, "Lists must be homogeneous"})

      true ->
        list
    end
  end
end
