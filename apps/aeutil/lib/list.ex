defmodule Aeutil.List do
  @moduledoc """
  This module holds some additional utility functions for list
  """

  @doc """
  Merge two list in descending order
  """
  @spec merge_descending(list(), list()) :: list()
  def merge_descending(list1, list2) do
    merge(list1, list2, [])
  end

  defp merge([], [], acc) do
    acc
    |> Enum.reverse()
  end

  defp merge([], [head2 | rest2], acc) do
    merge([], rest2, [head2 | acc])
  end

  defp merge([head1 | rest1], [], acc) do
    merge(rest1, [], [head1 | acc])
  end

  defp merge(
         [%{height: height1} = hd1 | rest1] = list1,
         [%{height: height2} = hd2 | rest2] = list2,
         acc
       ) do
    cond do
      height1 > height2 ->
        merge(rest1, list2, [hd1 | acc])

      height1 < height2 ->
        merge(list1, rest2, [hd2 | acc])

      true ->
        merge(rest1, rest2, [hd1 | acc])
    end
  end
end
