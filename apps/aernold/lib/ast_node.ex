defmodule ASTNode do

  alias Aecore.Chain.Worker, as: Chain

  def evaluate({{:contract, _}, _id, body}, {prev_val, scope}) do
    Enum.reduce(body, {prev_val, scope}, fn(statement, {prev_val_acc, scope_acc}) ->
      evaluate(statement, {prev_val_acc, scope_acc})
    end)
  end

  def evaluate({:id, _} = id, {_prev_val, scope}) do
    value = Reducer.to_value(id, {nil, scope})
    {value, scope}
  end

  def evaluate({:decl_var, {_, id}, {_, type}}, {_prev_val, scope}) do
    default_value = Reducer.to_value(type, {nil, scope})
    scope = Map.put(scope, id, %{type: type, value: default_value})
    {default_value, scope}
  end

  def evaluate({:def_var, {_, id}, {_, type}, value}, {_prev_val, scope}) do
    extracted_value = Reducer.to_value(value, {nil, scope})

    ASTNodeUtils.validate_variable_value!(id, type, extracted_value, scope)

    scope = Map.put(scope, id, %{type: type, value: extracted_value})
    {extracted_value, scope}
  end

  def evaluate({{:id, id}, {:=, _}, value}, {_prev_val, scope}) do
    extracted_value = Reducer.to_value(value, {nil, scope})
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
          condition_result = Reducer.to_value(condition, {nil, scope})
          if condition_result do
            {statement_result, statement_scope} =
              Enum.reduce(body, {nil, scope}, fn(statement, {prev_val_acc, scope_acc}) ->
                ASTNode.evaluate(statement, {prev_val_acc, scope_acc})
              end)

            {true, {statement_result, statement_scope}}
          else
            {false, {prev_val_acc, scope_acc}}
          end
        end
      end)

    {if_statement_val, if_statement_scope}
  end

  ## Arithmetic operations
  def evaluate({lhs, {:+, _}, rhs}, {_prev_val, scope}) do
    result = Reducer.to_value(lhs, {nil, scope}) + Reducer.to_value(rhs, {nil, scope})
    {result, scope}
  end

  def evaluate({lhs, {:-, _}, rhs}, {_prev_val, scope}) do
    result = Reducer.to_value(lhs, {nil, scope}) - Reducer.to_value(rhs, {nil, scope})
    {result, scope}
  end

  def evaluate({lhs, {:*, _}, rhs}, {_prev_val, scope}) do
    result = Integer.floor_div(Reducer.to_value(lhs, {nil, scope}), Reducer.to_value(rhs, {nil, scope}))
    {result, scope}
  end

  def evaluate({lhs, {:*, _}, rhs}, {_prev_val, scope}) do
    result = Reducer.to_value(lhs, {nil, scope}) * Reducer.to_value(rhs, {nil, scope})
    {result, scope}
  end

  ##Equality operators
  def evaluate({lhs, {:==, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = if lhs_value == rhs_value, do: true, else: false
    {result, scope}
  end

  def evaluate({lhs, {:!=, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = result = if lhs_value != rhs_value, do: true, else: false
    {result, scope}
  end

  ## Relational operators
  def evaluate({lhs, {:>, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = if lhs_value > rhs_value, do: true, else: false
    {result, scope}
  end

  def evaluate({lhs, {:>=, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = if lhs_value >= rhs_value, do: true, else: false
    {result, scope}
  end

  def evaluate({lhs, {:<, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = if lhs_value < rhs_value, do: true, else: false
    {result, scope}
  end

  def evaluate({lhs, {:<=, _}, rhs}, {_prev_val, scope}) do
    lhs_value = Reducer.to_value(lhs, {nil, scope})
    rhs_value = Reducer.to_value(rhs, {nil, scope})

    result = if lhs_value <= rhs_value, do: true, else: false
    {result, scope}
  end

  ##Logic operators
  #TODO: discuss if we want logic operators outside if statements
  # def evaluate({lhs, {:&&, _}, rhs}, {_prev_val, scope}) do
  #   lhs_value = Reducer.to_value(lhs, {nil, scope})
  #   rhs_value = Reducer.to_value(rhs, {nil, scope})
  #
  #   if lhs_value && rhs_value, do: true, else: false
  # end
  #
  # def evaluate({lhs, {:||, _}, rhs}, {_prev_val, scope}) do
  #   lhs_value = Reducer.to_value(lhs, {nil, scope})
  #   rhs_value = Reducer.to_value(rhs, {nil, scope})
  #
  #   if lhs_value || rhs_value, do: true, else: false
  # end

  def evaluate({:func_call, {_, 'account_balance'}, {param}}, {_prev_val, scope}) do
    {_, extracted_param} = Reducer.to_value(param, {nil, scope}) |> Base.decode16()
      balance = case(Chain.chain_state[extracted_param]) do
        nil ->
          0
        %{balance: balance} ->
        balance
      end
    {balance, scope}
  end

  def evaluate({:func_definition, {_, id}, _, _} = func, {_prev_val, scope}) do
    {nil, Map.put(scope, id, func)}
  end

  def evaluate({:func_call, id, args}, {_prev_val, scope}) do
    func_returned_value = Reducer.to_value({:func_call, id, args}, {nil, scope})

    {func_returned_value, scope}
  end

  def evaluate({:int, int}, {_, scope}) do
    evaluate_raw_value({:int, int}, {nil, scope})
  end

  def evaluate({:bool, bool}, {_, scope}) do
    evaluate_raw_value({:bool, bool}, {nil, scope})
  end

  def evaluate({:hex, hex}, {_, scope}) do
    evaluate_raw_value({:hex, hex}, {nil, scope})
  end

  def evaluate({:char, char}, {_, scope}) do
    evaluate_raw_value({:char, char}, {nil, scope})
  end

  def evaluate({:string, string}, {_, scope}) do
    evaluate_raw_value({:string, string}, {nil, scope})
  end

  defp evaluate_raw_value(node, {prev_val, scope}) do
    extracted_value = Reducer.to_value(node, {prev_val, scope})

    {extracted_value, scope}
  end

end
