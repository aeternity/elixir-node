defmodule ASTNode do

  alias Aecore.Chain.Worker, as: Chain

  def evaluate({{:contract, _}, _id, params, args, body}, {prev_val, scope}) do
    {_, scope} = Enum.reduce(params, {0, scope}, fn(param, {args_index, scope_acc}) ->
      arg = elem(args, args_index)
      {_, id, type} = param
      var_def = {:def_var, id, type, arg}

      {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
      {args_index + 1, scope_acc}
    end)

    Enum.reduce(body, {prev_val, scope}, fn(statement, {prev_val_acc, scope_acc}) ->
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
    tuple_values = if values != :empty do
      Enum.reduce(values, [], fn(value, acc) -> [elem(evaluate(value, {nil, scope}), 0) | acc] end)
      |> Enum.reverse
      |> List.to_tuple
    else
      {}
    end

    scope = Map.put(scope, id, %{type: type, value: tuple_values})

    {tuple_values, scope}
  end

  def evaluate({:decl_list, {_, id}, {_, type}, {_, list_type}}, {_prav_val, scope}) do
    {default_value, _} = evaluate(type, {nil, scope})

    scope = if type == 'List' do
      Map.put(scope, id, %{type: {type, list_type}, value: default_value})
    else
      throw ({:error, "The type of (#{id}) must be List"})
    end

    {default_value, scope}
  end

  def evaluate({:def_list, {_, id}, {_, type}, {_, list_type}, values}, {_prev_val, scope}) do
    list_values = if type == 'List' do
      if values != :empty do
        Enum.reduce(values, [], fn(value, acc) ->
          {curr_value, _} = evaluate(value, {nil, scope})
          if ASTNodeUtils.validate_variable_value!(id, list_type, curr_value, scope) == :ok do
            [elem(evaluate(value, {nil, scope}), 0) | acc]
          end
        end)
        |> Enum.reverse
      else
        []
      end
    else
      throw ({:error, "The type of (#{id}) must be List"})
    end

    scope = Map.put(scope, id, %{type: {type, list_type}, value: list_values})

    {list_values, scope}
  end

  def evaluate({{:id, id}, {:=, _}, value}, {_prev_val, scope}) do
    {extracted_value, _} = evaluate(value, {nil, scope})
    %{type: type} = Map.get(scope, id)

    ASTNodeUtils.validate_variable_value!(id, type, extracted_value, scope)

    scope = Map.put(scope, id, %{type: type, value: extracted_value})

    {extracted_value, scope}
  end

  def evaluate({:if_statement, statements}, {_prev_val, scope}) do
    {_, {if_statement_val, if_statement_scope}} = Enum.reduce(statements, {false, {nil, scope}},
      fn({condition, body}, {has_true_condition, {prev_val_acc, scope_acc}}) ->
        if has_true_condition do
          {has_true_condition, {prev_val_acc, scope_acc}}
        else
          {condition_result, _} = evaluate(condition, {nil, scope})
          if condition_result do
            {statement_result, statement_scope} =
              Enum.reduce(body, {nil, scope}, fn(statement, {prev_val_acc, scope_acc}) ->
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
    {_, {switch_statement_val, switch_statement_scope}} = Enum.reduce(cases, {false, {nil, scope}},
      fn({case_param, body}, {has_matched_case, {prev_val_acc, scope_acc}}) ->
        if has_matched_case do
          {has_matched_case, {prev_val_acc, scope_acc}}
        else
          {case_param_value, _} = evaluate(case_param, {nil, scope})
          if case_param_value == param_extracted_value do
            {statement_result, statement_scope} =
              Enum.reduce(body, {nil, scope}, fn(statement, {prev_val_acc, scope_acc}) ->
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

  # Arithmetic operations
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

  #Equality operators
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

  # Relational operators
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

  ##Logic operators
  #TODO: discuss if we want logic operators outside if statements
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

  def evaluate({:func_call, {_, 'print'}, {param}}, {_prev_val, scope}) do
    {extracted_param, _} = evaluate(param, {nil, scope})
    {IO.inspect(extracted_param), scope}
  end

  def evaluate({:func_call, {_, 'account_balance'}, {param}}, {_prev_val, scope}) do
    {extracted_param, _} = evaluate(param, {nil, scope})
    {_, decoded_extracted_param} = Base.decode16(extracted_param)
    balance =
      case(Chain.chain_state[decoded_extracted_param]) do
        nil ->
          0
        %{balance: balance} ->
          balance
      end

    {balance, scope}
  end

  def evaluate({:func_call, {_, 'elem'}, {data_struct, index}}, {_prev_val, scope}) do
    {extracted_data_struct, _} = evaluate(data_struct, {nil, scope})
    {extracted_index, _} = evaluate(index, {nil, scope})

    result = cond do
      is_tuple(extracted_data_struct) == true -> elem(extracted_data_struct, extracted_index)
      is_list(extracted_data_struct) == true -> Enum.at(extracted_data_struct, extracted_index)
    end

    {result, scope}
  end

  def evaluate({:func_call, {_, 'size'}, {data_struct}}, {_prev_val, scope}) do
    {extracted_data_struct, _} = evaluate(data_struct, {nil, scope})

    result = cond do
      is_tuple(extracted_data_struct) == true -> tuple_size(extracted_data_struct)
      is_list(extracted_data_struct) == true -> Enum.count(extracted_data_struct)
    end

    {result, scope}
  end

  ##TODO: not working right now
  def evaluate({:func_call, {_, 'insert_at'}, {list, index, value}}, {_prev_val, scope}) do
    {extracted_list} = evaluate(list, {nil, scope})
    {extracted_index} = evaluate(index, {nil, scope})
    {extracted_value} = evaluate(value, {nil, scope})

    result = List.insert_at(extracted_list, extracted_index, extracted_value)

    {result, scope}
  end

  ##TODO: not working right now
  def evaluate({:func_call, {_, 'append'}, {tuple, value}}, {_prev_val, scope}) do
    {extracted_value} = evaluate(value, {nil, scope})
    {extracted_tuple} = evaluate(tuple, {nil, scope})

    result = Tuple.append(extracted_tuple, extracted_value)

    {result, scope}
  end

  def evaluate({:func_definition, {_, id}, _, _} = func, {_prev_val, scope}) do
    {nil, Map.put(scope, id, func)}
  end

  def evaluate({:func_call, id, args}, {_prev_val, scope}) do
    {_, func_name} = id
    {_, {_, _, params, body} = func} = Enum.find(scope, fn(s) ->
      scope_key = elem(s, 0)
      scope_val = elem(s, 1)
      if !is_map(scope_val) do
        elem(scope_val, 0) == :func_definition && scope_key == func_name
      else
        false
      end
    end)

    {_, scope} = Enum.reduce(params, {0, scope}, fn(param, {args_index, scope_acc}) ->
      arg = elem(args, args_index)
      {_, id, type} = param
      var_def = {:def_var, id, type, arg}

      {_, scope_acc} = evaluate(var_def, {nil, scope_acc})
      {args_index + 1, scope_acc}
    end)

    {func_returned_value, scope} = Enum.reduce(body, {nil, scope}, fn(statement, {prev_val, scope_acc}) ->
      evaluate(statement, {prev_val, scope_acc})
    end)

    {func_returned_value, scope}
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
    {List.to_string([char]), scope}
  end

  def evaluate('Char', {_, scope}) do
    {'', scope}
  end

  def evaluate({:string, string}, {_, scope}) do
    {string, scope}
  end

  def evaluate({:tuple, values}, {_, scope}) do
    tuple_values = if values != :empty do
      Enum.reduce(values, [], fn(value, acc) -> [elem(evaluate(value, {nil, scope}), 0) | acc] end)
      |> Enum.reverse
      |> List.to_tuple
    else
      {}
    end

    {tuple_values, scope}
  end

  def evaluate('Tuple', {_, scope}) do
    {{}, scope}
  end

  #TODO: make independent lists homogenous as well
  def evaluate({:list, values}, {_, scope}) do
    list_values = if values != :empty do
      Enum.reduce(values, [], fn(value, acc) ->
        {curr_value, _} = evaluate(value, {nil, scope})
        [elem(evaluate(value, {nil, scope}), 0) | acc]
      end)
      |> Enum.reverse
    else
      []
    end

    {list_values, scope}
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
