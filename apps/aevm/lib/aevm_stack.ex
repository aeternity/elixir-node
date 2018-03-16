defmodule AevmStack do
  def new() do
    []
  end

  def push(stack, arg) do
    [arg | stack]
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
      stack =
        case length(stack) < index do
          true ->
            throw({"stack_too_small_for_dup", stack})

          false ->
            value = Enum.at(stack, index)
            push(stack, value)
        end
    end
  end
end
