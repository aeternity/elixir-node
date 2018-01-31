defmodule Tuple.Enumerable do
  defimpl Enumerable, for: Tuple do
    @max_items 42

    def count(tuple), do: tuple_size(tuple)

    # member? implementation is done through casting tuple to the list
    #  it’s not required for iteration, and building all those matched
    #  clauses seems to be an overkill here
    def member?([], _), do: {:ok, false}
    def member?(tuple, value) when is_tuple(tuple) do
      tuple |> Tuple.to_list |> member?(value)
    end
    def member?(tuple, value) when is_list(tuple) do
      for [h | t] <- tuple do
        if h == value, do: {:ok, true}, else: member?(t, value)
      end
    end


    def reduce(tuple, acc, fun) do
      do_reduce(tuple, acc, fun)
    end

    defp do_reduce(_,       {:halt, acc}, _fun),   do: {:halted, acc}
    defp do_reduce(tuple,   {:suspend, acc}, fun)  do
      {:suspended, acc, &do_reduce(tuple, &1, fun)}
    end
    defp do_reduce({},      {:cont, acc}, _fun),   do: {:done, acc}
    defp do_reduce({value}, {:cont, acc}, fun),    do: do_reduce({}, fun.(value, acc), fun)

    Enum.each(1..@max_items-1, fn tot ->
      tail = Enum.join(Enum.map(1..tot, & "e_#{&1}"), ",")
      match = Enum.join(["value"] ++ [tail], ",")
      Code.eval_string(
        "defp do_reduce({#{match}}, {:cont, acc}, fun), do: do_reduce({#{tail}}, fun.(value, acc), fun)", [], __ENV__
      )
    end)

    # list fallback for huge tuples
    defp do_reduce([h | t], {:cont, acc}, fun)     do
      do_reduce((if Enum.count(t) <= @max_items, do: List.to_tuple(t), else: t), fun.(h, acc), fun)
    end

    # fallback to list for huge tuples
    defp do_reduce(huge,    {:cont, acc}, fun) when huge > @max_items do
      do_reduce(Tuple.to_list(huge), {:cont, acc}, fun)
    end
  end
end
