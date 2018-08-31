defmodule Aeutil.List do
  @moduledoc """
  This module holds some additional utility functions for list
  """

  @doc """
  Merge two list in descending order
  """
  @spec merge_descending(list(), list()) :: list()
  def merge_descending(list_1, list_2) do
    merge_descending(list_1, list_2, [])
  end

  @spec merge_descending(list(), list(), list()) :: list()
  defp merge_descending([], [], acc) do
    acc
    |> Enum.sort()
    |> Enum.reverse()
  end

  defp merge_descending([], [head2 | list_2], acc) do
    merge_descending([], list_2, [head2 | acc])
  end

  defp merge_descending([head1 | list_1], list_2, acc) do
    case Enum.member?(list_2, head1) do
      true ->
        new_list_2 = Enum.filter(list_2, fn elem -> elem != head1 end)
        merge_descending(list_1, new_list_2, [head1 | acc])

      false ->
        merge_descending(list_1, list_2, [head1 | acc])
    end
  end
end
