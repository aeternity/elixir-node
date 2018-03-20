defmodule AevmStack do
  def new() do
    []
  end

  def push(stack, arg) do
    if length(stack) < 1024 do
      [arg | stack]
    else
      throw({"out_of_stack", stack})
    end
  end

  def pop(stack) do
    case stack do
      [arg | stack] -> {arg, stack}
      [] -> throw({"emtpy_stack", stack})
    end
  end

  def peek(stack, index) when index >= 0 do
    if Enum.empty?(stack) do
      throw({"empty stack", stack})
    else
      case Enum.at(stack, index) do
        nil -> throw({"stack_too_small", stack})
        _ -> Enum.at(stack, index)
      end
    end
  end

  def dup(stack, index) do
    if Enum.empty?(stack) do
      throw({"empty stack", stack})
    else
      case length(stack) < index do
        true ->
          throw({"stack_too_small_for_dup", stack})

        false ->
          value = Enum.at(stack, index)
          push(stack, value)
      end
    end
  end

  def swap(stack, index) do
    if Enum.empty?(stack) do
      throw({"empty stack", stack})
    else
      [top | rest] = stack

      case length(rest) < index do
        true ->
          throw({"stack_too_small_for_swap", stack})

        false ->
          index_elem = Enum.at(rest, index)
          stack = [index_elem, set_val(index, top, rest)]
          List.flatten(stack)
      end
    end
  end

  def set_val(0, val, [_ | rest]) do
    [val | rest]
  end

  def set_val(index, val, [elem | rest]) do
    [elem | set_val(index - 1, val, rest)]
  end
end
