defmodule Aeutil.List do
  @moduledoc """
  This module holds some additional utility functions for list
  """

  @spec merge(list(), list()) :: list()
  def merge(l1, l2) do
    do_merge(Enum.reverse(l1), Enum.reverse(l2), [])
  end

  defp do_merge([], [], acc), do: acc

  defp do_merge([], [h | t], [last | _] = acc) do
    if h === last do
      do_merge([], t, acc)
    else
      do_merge([], t, [h | acc])
    end
  end

  defp do_merge([], [h | t], []) do
    do_merge([], t, [h])
  end

  defp do_merge(l, [], acc) do
    ## reuse the code
    do_merge([], l, acc)
  end

  defp do_merge([h1 | _] = l1, [h2 | t2], []) when h1 < h2 do
    do_merge(l1, t2, [h2])
  end

  defp do_merge([h1 | t1], l2, []) do
    do_merge(t1, l2, [h1])
  end

  defp do_merge([h1 | t1] = l1, [h2 | t2] = l2, [last | _] = acc) do
    cond do
      h1 === last -> do_merge(t1, l2, acc)
      h2 === last -> do_merge(l1, t2, acc)
      h1 === h2 -> do_merge(t1, t2, [h1 | acc])
      h1 < h2 -> do_merge(l1, t2, [h2 | acc])
      h1 > h2 -> do_merge(t1, l2, [h1 | acc])
    end
  end
end
