defmodule ASTNode do
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool

  def evaluate({{:contract, _}, _id, params, args, body}, {prev_val, scope}) do
    {_, scope} =
      Enum.reduce(params, {0, scope}, fn param, {args_index, scope_acc} ->
        arg = elem(args, args_index)

        case param do
          {_, id, type} ->
            var_def = {:def_var, id, type, arg}

            {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
            {args_index + 1, scope_acc}

          {_, id, type, list_type} ->
            list_def = {:decl_list, id, type, list_type}

            {_, scope_acc} = evaluate(list_def, {nil, scope_acc})
            {args_index + 1, scope_acc}

          {_, id, type, keys_type, values_type} ->
            map_def = {:decl_map, id, type, keys_type, values_type}

            {_, scope_acc} = evaluate(map_def, {nil, scope_acc})
            {args_index + 1, scope_acc}
        end
      end)

    Enum.reduce(body, {prev_val, scope}, fn statement, {prev_val_acc, scope_acc} ->
      evaluate(statement, {prev_val_acc, scope_acc})
    end)
  end

  def evaluate({:id, id}, {_prev_val, scope}) do
    if !Map.has_key?(scope, id) do
      throw({:error, "Undefined variable (#{id})"})
    end

    %{value: value} = Map.get(scope, id)

    {value, scope}
  end

  def evaluate({:type, type}, {_prev_val, scope}) do
    {type, scope}
  end

  def evaluate({:decl_var, {_, id}, {_, type}}, {_prev_val, scope}) do
    {default_value, _} = evaluate(type, {nil, scope})
    scope = Map.put(scope, id, %{type: type, value: default_value})

    {default_value, scope}
  end

  def evaluate({:def_var, {_, id}, {_, type}, value}, {_prev_val, scope}) do
    {extracted_value, _} = evaluate(value, {nil, scope})

    ASTNodeUtils.validate_variable_value!(id, type, extracted_value, scope)

    scope = Map.put(scope, id, %{type: type, value: extracted_value})

    {extracted_value, scope}
  end

  def evaluate({:def_tuple, {_, id}, {_, type}, values}, {_prev_val, scope}) do
    tuple_values =
      if values != :empty do
        Enum.reduce(values, [], fn value, acc ->
          [elem(evaluate(value, {nil, scope}), 0) | acc]
        end)
        |> Enum.reverse()
        |> List.to_tuple()
      else
        {}
      end

    scope = Map.put(scope, id, %{type: type, value: tuple_values})

    {tuple_values, scope}
  end

  def evaluate({:decl_list, {_, id}, {_, type}, {_, list_type}}, {_prav_val, scope}) do
    {default_value, _} = evaluate(type, {nil, scope})

    scope =
      if type == 'List' do
        Map.put(scope, id, %{type: {type, list_type}, value: default_value})
      else
        throw({:error, "The type of (#{id}) must be List"})
      end

    {default_value, scope}
  end

  def evaluate({:def_list, {_, id}, {_, type}, {_, list_type}, values}, {_prev_val, scope}) do
    list_values =
      if type == 'List' do
        if values != :empty do
          Enum.reduce(values, [], fn value, acc ->
            {curr_value, _} = evaluate(value, {nil, scope})

            if ASTNodeUtils.validate_variable_value!(id, list_type, curr_value, scope) == :ok do
              [elem(evaluate(value, {nil, scope}), 0) | acc]
            end
          end)
          |> Enum.reverse()
        else
          []
        end
      else
        throw({:error, "The type of (#{id}) must be List"})
      end

    scope = Map.put(scope, id, %{type: {type, list_type}, value: list_values})

    {list_values, scope}
  end

  def evaluate(
        {:decl_map, {_, id}, {_, 'Map' = type}, {_, keys_type}, {_, values_type}},
        {_prev_val, scope}
      ) do
    scope = Map.put(scope, id, %{type: {type, {keys_type, values_type}}, value: %{}})

    {nil, scope}
  end

  def evaluate(
        {:def_map, {_, id}, {_, 'Map' = type}, {_, keys_type}, {_, values_type}, map_values},
        {_prev_val, scope}
      ) do
    map =
      Enum.reduce(map_values, %{}, fn {{key_type, key_value} = key,
                                       {_value_type, value_value} = value},
                                      acc ->
        {key_extracted_value, _} = evaluate(key, {nil, scope})
        ASTNodeUtils.validate_map_key_or_value!(keys_type, key_extracted_value)

        {value_extracted_value, _} = evaluate(value, {nil, scope})
        ASTNodeUtils.validate_map_key_or_value!(values_type, value_extracted_value)

        map_key = ASTNodeUtils.value_to_map_key!(key_type, key_value)

        Map.put(acc, map_key, value_value)
      end)

    scope = Map.put(scope, id, %{type: {type, {keys_type, values_type}}, value: map})

    {map, scope}
  end

  def evaluate({{:id, id}, {:=, _}, value}, {_prev_val, scope}) do
    {extracted_value, _} = evaluate(value, {nil, scope})
    %{type: type} = Map.get(scope, id)

    ASTNodeUtils.validate_variable_value!(id, type, extracted_value, scope)

    scope = Map.put(scope, id, %{type: type, value: extracted_value})

    {extracted_value, scope}
  end

  def evaluate({:if_statement, statements}, {_prev_val, scope}) do
    {_, {if_statement_val, if_statement_scope}} =
      Enum.reduce(statements, {false, {nil, scope}}, fn {condition, body},
                                                        {has_true_condition,
                                                         {prev_val_acc, scope_acc}} ->
        if has_true_condition do
          {has_true_condition, {prev_val_acc, scope_acc}}
        else
          {condition_result, _} = evaluate(condition, {nil, scope})

          if condition_result do
            {statement_result, statement_scope} =
              Enum.reduce(body, {nil, scope}, fn statement, {prev_val_acc, scope_acc} ->
                evaluate(statement, {prev_val_acc, scope_acc})
              end)

            {true, {statement_result, statement_scope}}
          else
            {false, {prev_val_acc, scope_acc}}
          end
        end
      end)

    updated_scope = ASTNodeUtils.update_scope(scope, if_statement_scope)

    {if_statement_val, updated_scope}
  end

  def evaluate({:switch_statement, {param, cases}}, {prev_val, scope}) do
    {param_extracted_value, _} = evaluate(param, {prev_val, scope})

    {_, {switch_statement_val, switch_statement_scope}} =
      Enum.reduce(cases, {false, {nil, scope}}, fn {case_param, body},
                                                   {has_matched_case, {prev_val_acc, scope_acc}} ->
        if has_matched_case do
          {has_matched_case, {prev_val_acc, scope_acc}}
        else
          {case_param_value, _} = evaluate(case_param, {nil, scope})

          if case_param_value == param_extracted_value do
            {statement_result, statement_scope} =
              Enum.reduce(body, {nil, scope}, fn statement, {prev_val_acc, scope_acc} ->
                evaluate(statement, {prev_val_acc, scope_acc})
              end)

            {true, {statement_result, statement_scope}}
          else
            {false, {prev_val_acc, scope_acc}}
          end
        end
      end)

    updated_scope = ASTNodeUtils.update_scope(scope, switch_statement_scope)

    {switch_statement_val, updated_scope}
  end

  # TODO: to be refactored!
  def evaluate(
        {:foreach_statement, {{_, id}, as, statements}} = a,
        {prev_val, scope}
      ) do
    {_, %{type: {type, values_type}} = variable} =
      Enum.find(scope, fn s ->
        scope_key = elem(s, 0)
        scope_val = elem(s, 1)

        %{type: {type, _}} = scope_val

        is_map(scope_val) && scope_key == id && Enum.member?(['List', 'Map'], type)
      end)

    if variable == nil do
      throw({:error, "Invalid type passed to foreach"})
    end

    {returned_value, updated_scope} =
      variable.value
      |> Stream.with_index()
      |> Enum.reduce({nil, scope}, fn {value, key}, {returned_value, scope_acc} ->
        {key, value} =
          case type do
            'List' ->
              {key, value}

            'Map' ->
              {key, value} = value
          end

        values_type =
          if !is_tuple(values_type) do
            Tuple.append({}, values_type)
          else
            values_type
          end

        {_, value_as} = elem(as, tuple_size(as) - 1)

        value_type_charlist = elem(values_type, tuple_size(values_type) - 1)

        value_type_atom =
          value_type_charlist |> List.to_string() |> String.downcase() |> String.to_atom()

        var_def =
          {:def_var, {:id, value_as}, {:type, value_type_charlist}, {value_type_atom, value}}

        {_, scope_acc} = evaluate(var_def, {nil, scope_acc})

        scope_acc =
          if tuple_size(as) == 2 do
            {_, key_as} = elem(as, 0)

            if tuple_size(values_type) == 1 do
              var_def = {:def_var, {:id, key_as}, {:type, 'Int'}, {:int, key}}

              {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
              scope_acc
            else
              key_type_charlist = elem(values_type, 0)

              key_type_atom =
                value_type_charlist |> List.to_string() |> String.downcase() |> String.to_atom()

              var_def =
                {:def_var, {:id, key_as}, {:type, key_type_charlist}, {key_type_atom, key}}

              {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
              scope_acc
            end
          else
            scope_acc
          end

        {returned_value, scope_acc} =
          Enum.reduce(statements, {nil, scope_acc}, fn s, {prev_val, scope_acc} ->
            evaluate(s, {prev_val, scope_acc})
          end)

        {returned_value, scope_acc}
      end)

    {returned_value, updated_scope}
  end

  ## Arithmetic operations
  def evaluate({lhs, {:+, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = lhs_value + rhs_value

    {result, scope}
  end

  def evaluate({lhs, {:-, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = lhs_value - rhs_value

    {result, scope}
  end

  def evaluate({lhs, {:*, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = lhs_value * rhs_value

    {result, scope}
  end

  def evaluate({lhs, {:/, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = Integer.floor_div(lhs_value, rhs_value)

    {result, scope}
  end

  def evaluate({lhs, {:%, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = rem(lhs_value, rhs_value)

    {result, scope}
  end

  def evaluate({lhs, {:++, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result =
      cond do
        !is_list(lhs_value) ->
          throw({:error, "Argument error, value must be list"})

        !is_list(rhs_value) ->
          throw({:error, "Argument error, value must be list"})

        true ->
          lhs_value ++ rhs_value
      end

    ASTNodeUtils.check_list_item_type(result)

    {result, scope}
  end

  def evaluate({lhs, {:--, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result =
      cond do
        !is_list(lhs_value) ->
          throw({:error, "Argument error, value must be list"})

        !is_list(rhs_value) ->
          throw({:error, "Argument error, value must be list"})

        true ->
          lhs_value -- rhs_value
      end

    ASTNodeUtils.check_list_item_type(result)

    {result, scope}
  end

  ## Equality operators
  def evaluate({lhs, {:==, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value == rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:!=, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value != rhs_value, do: true, else: false

    {result, scope}
  end

  ## Relational operators
  def evaluate({lhs, {:>, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value > rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:>=, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value >= rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:<, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value < rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:<=, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value <= rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:&&, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value && rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({lhs, {:||, _}, rhs}, {_prev_val, scope}) do
    {lhs_value, _} = evaluate(lhs, {nil, scope})
    {rhs_value, _} = evaluate(rhs, {nil, scope})

    result = if lhs_value || rhs_value, do: true, else: false

    {result, scope}
  end

  def evaluate({:func_call, {_, 'print'}, {value}}, {_prev_val, scope}) do
    {extracted_value, _} = evaluate(value, {nil, scope})

    {IO.inspect(extracted_value), scope}
  end

  def evaluate({:func_call, {_, 'account_balance'}, {account}}, {_prev_val, scope}) do
    {extracted_account, _} = evaluate(account, {nil, scope})
    {_, decoded_extracted_account} = Base.decode16(extracted_account)

    balance =
      case Chain.chain_state()[decoded_extracted_account] do
        nil ->
          0

        %{balance: balance} ->
          balance
      end

    {balance, scope}
  end

  ## it does nothing special for now
  def evaluate({:func_call, {_, 'txs_for_account'}, {account}}, {_prev_val, scope}) do
    {extracted_account, _} = evaluate(account, {nil, scope})
    {_, decoded_extracted_account} = Base.decode16(extracted_account)

    account_txs = Pool.get_txs_for_address(decoded_extracted_account)

    {account_txs, scope}
  end

  ## List functions

  def evaluate({:func_call, {_, 'List'}, {_, 'at'}, {list, index}}, {_prev_val, scope}) do
    {extracted_list, _} = evaluate(list, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})

    result = Enum.at(extracted_list, extracted_index)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'List'}, {_, 'size'}, {list}}, {_prev_val, scope}) do
    {extracted_list, _} = evaluate(list, {nil, scope})

    result = Enum.count(extracted_list)

    {result, scope}
  end

  def evaluate(
        {:func_call, {_, 'List'}, {_, 'insert_at'}, {list, index, value}},
        {_prev_val, scope}
      ) do
    {extracted_list, _} = evaluate(list, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})
    {extracted_value, _} = evaluate(value, {nil, scope})

    result = List.insert_at(extracted_list, extracted_index, extracted_value)

    if is_list(result) do
      ASTNodeUtils.check_list_item_type(result)
    end

    {result, scope}
  end

  def evaluate({:func_call, {_, 'List'}, {_, 'delete_at'}, {list, index}}, {_prev_val, scope}) do
    {extracted_list, _} = evaluate(list, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})

    result = List.delete_at(extracted_list, extracted_index)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'List'}, {_, 'reverse'}, {list}}, {_prev_val, scope}) do
    {extracted_list, _} = evaluate(list, {nil, scope})

    result = Enum.reverse(extracted_list)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'List'}, {_, 'sort'}, {list}}, {_prev_val, scope}) do
    {extracted_list, _} = evaluate(list, {nil, scope})

    result = Enum.sort(extracted_list)

    {result, scope}
  end
  ## Tuple functions

  def evaluate({:func_call, {_, 'Tuple'}, {_, 'elem'}, {tuple, index}}, {_prev_val, scope}) do
    {extracted_tuple, _} = evaluate(tuple, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})

    result = elem(extracted_tuple, extracted_index)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'Tuple'}, {_, 'size'}, {tuple}}, {_prev_val, scope}) do
    {extracted_tuple, _} = evaluate(tuple, {nil, scope})

    result = tuple_size(extracted_tuple)

    {result, scope}
  end

  def evaluate(
        {:func_call, {_, 'Tuple'}, {_, 'insert_at'}, {tuple, index, value}},
        {_prev_val, scope}
      ) do
    {extracted_tuple, _} = evaluate(tuple, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})
    {extracted_value, _} = evaluate(value, {nil, scope})

    result = Tuple.insert_at(extracted_tuple, extracted_index, extracted_value)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'Tuple'}, {_, 'delete_at'}, {tuple, index}}, {_prev_val, scope}) do
    {extracted_tuple, _} = evaluate(tuple, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})

    result = Tuple.delete_at(extracted_tuple, extracted_index)

    {result, scope}
  end

  def evaluate({:func_call, {_, 'Tuple'}, {_, 'append'}, {tuple, value}}, {_prev_val, scope}) do
    {extracted_tuple, _} = evaluate(tuple, {nil, scope})
    {extracted_value, _} = evaluate(value, {nil, scope})

    result = Tuple.append(extracted_tuple, extracted_value)

    {result, scope}
  end

  ## Map functions

  def evaluate(
        {:func_call, {_, 'Map'}, {_, 'get'}, {{_, id} = map_id, {_key_type, _key_value} = key}},
        {_prev_val, scope}
      ) do
    {extracted_map, _} = evaluate(map_id, {nil, scope})
    {extracted_key, _} = evaluate(key, {nil, scope})

    {_, {map_key_type, _map_value_type}} = Map.get(scope, id).type

    ASTNodeUtils.validate_map_key_or_value!(map_key_type, extracted_key)

    result = Map.get(extracted_map, extracted_key)

    {result, scope}
  end

  def evaluate(
        {:func_call, {_, 'Map'}, {_, 'put'},
         {{_, id} = map_id, {key_type, key_value} = key, value}},
        {_prev_val, scope}
      ) do
    {extracted_map, _} = evaluate(map_id, {nil, scope})
    {extracted_key, _} = evaluate(key, {nil, scope})
    {extracted_value, _} = evaluate(value, {nil, scope})

    {_, {map_key_type, map_value_type}} = Map.get(scope, id).type

    ASTNodeUtils.validate_map_key_or_value!(map_key_type, extracted_key)
    ASTNodeUtils.validate_map_key_or_value!(map_value_type, extracted_value)

    result =
      Map.put(extracted_map, ASTNodeUtils.value_to_map_key!(key_type, key_value), extracted_value)

    {result, scope}
  end

  def evaluate(
        {:func_call, {_, 'Map'}, {_, 'delete'}, {{_, id} = map_id, {_key_type, _key_value} = key}},
        {_prev_val, scope}
      ) do
    {extracted_map, _} = evaluate(map_id, {nil, scope})
    {extracted_key, _} = evaluate(key, {nil, scope})

    {_, {map_key_type, _map_value_type}} = Map.get(scope, id).type

    ASTNodeUtils.validate_map_key_or_value!(map_key_type, extracted_key)

    result = Map.delete(extracted_map, extracted_key)

    {result, scope}
  end

  def evaluate({:func_definition, {_, id}, _, _} = func, {_prev_val, scope}) do
    {nil, Map.put(scope, id, func)}
  end

  def evaluate({:func_call, id, args}, {_prev_val, scope}) do
    {_, func_name} = id
    initial_scope = scope

    {_, {_, _, params, body} = _func} =
      Enum.find(scope, fn s ->
        scope_key = elem(s, 0)
        scope_val = elem(s, 1)

        !is_map(scope_val) && elem(scope_val, 0) == :func_definition && scope_key == func_name
      end)

    initial_scope_size = Enum.count(scope)
    # initialize parameters in scope with the given arguments
    {_, scope} =
      Enum.reduce(params, {0, scope}, fn param, {args_index, scope_acc} ->
        arg = elem(args, args_index)

        case param do
          {_, _id, type} ->
            {_, {_, id}, _} = param
            # add private suffix to the parameter name
            # so that we don't overwrite it in the existing scope
            var_def = {:def_var, {:id, List.to_string(id) <> "_param"}, type, arg}

            {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
            {args_index + 1, scope_acc}

          {_, id, type, list_type} ->
            list_def = {:decl_list, id, type, list_type}

            {_, scope_acc} = evaluate(list_def, {nil, scope_acc})
            {args_index + 1, scope_acc}

          {_, id, type, keys_type, values_type} ->
            map_def = {:decl_map, id, type, keys_type, values_type}

            {_, scope_acc} = evaluate(map_def, {nil, scope_acc})
            {args_index + 1, scope_acc}
        end
      end)

    # revert the parameters' names to their original ones
    {_, scope} =
      Enum.reduce(scope, {1, %{}}, fn s, {current_index, scope_acc} ->
        scope_key = elem(s, 0)
        scope_val = elem(s, 1)

        if current_index <= initial_scope_size do
          {current_index + 1, Map.put(scope_acc, scope_key, scope_val)}
        else
          new_scope_key = scope_key |> String.replace("_param", "") |> String.to_charlist()

          {current_index + 1, Map.put(scope_acc, new_scope_key, scope_val)}
        end
      end)

    {func_returned_value, _scope} =
      Enum.reduce(body, {nil, scope}, fn statement, {prev_val, scope_acc} ->
        evaluate(statement, {prev_val, scope_acc})
      end)

    {func_returned_value, initial_scope}
  end

  def evaluate({:int, int}, {_, scope}) do
    {int, scope}
  end

  def evaluate('Int', {_, scope}) do
    {0, scope}
  end

  def evaluate({:bool, bool}, {_, scope}) do
    {bool, scope}
  end

  def evaluate('Bool', {_, scope}) do
    {false, scope}
  end

  def evaluate({:hex, hex}, {_, scope}) do
    {to_string(hex), scope}
  end

  def evaluate('Hex', {_, scope}) do
    {0x0, scope}
  end

  def evaluate({:char, char}, {_, scope}) do
    {[char], scope}
  end

  def evaluate('Char', {_, scope}) do
    {'', scope}
  end

  def evaluate({:string, string}, {_, scope}) do
    {string, scope}
  end

  def evaluate({:tuple, values}, {_, scope}) do
    tuple_values =
      if values != :empty do
        Enum.reduce(values, [], fn value, acc ->
          [elem(evaluate(value, {nil, scope}), 0) | acc]
        end)
        |> Enum.reverse()
        |> List.to_tuple()
      else
        {}
      end

    {tuple_values, scope}
  end

  def evaluate('Tuple', {_, scope}) do
    {{}, scope}
  end

  def evaluate({:list, values}, {_, scope}) do
    list_values =
      if values != :empty do
        Enum.reduce(values, [], fn value, acc ->
          [elem(evaluate(value, {nil, scope}), 0) | acc]
        end)
        |> Enum.reverse()
        |> ASTNodeUtils.check_list_item_type()
      else
        []
      end

    {list_values, scope}
  end

  def evaluate({:map, key_value_pairs}, {_, scope}) do
    map_values =
      if key_value_pairs != :empty do
        {{keys_type, _}, {values_type, _}} = elem(key_value_pairs, 0)

        Enum.reduce(key_value_pairs, %{}, fn {{_key_type, key_value} = key,
                                              {_value_type, value_value} = value},
                                             acc ->
          {key_extracted_value, _} = evaluate(key, {nil, scope})
          ASTNodeUtils.validate_map_key_or_value!(keys_type, key_extracted_value)

          {value_extracted_value, _} = evaluate(value, {nil, scope})
          ASTNodeUtils.validate_map_key_or_value!(values_type, value_extracted_value)

          map_key = ASTNodeUtils.value_to_map_key!(keys_type, key_value)

          Map.put(acc, map_key, value_value)
        end)
      else
        %{}
      end

    {map_values, scope}
  end

  def evaluate('List', {_, scope}) do
    {[], scope}
  end

  def evaluate_func_definitions({{:contract, _}, _id, _params, _args, body}, scope) do
    scope_with_functions =
      Enum.reduce(body, scope, fn statement, scope_acc ->
        case statement do
          {:func_definition, {_, id}, _, _} ->
            Map.put(scope_acc, id, statement)

          _ ->
            scope_acc
        end
      end)

    {nil, scope_with_functions}
  end
end
