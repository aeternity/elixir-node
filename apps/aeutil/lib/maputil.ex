defmodule Aeutil.MapUtil do
  @moduledoc """
  Some functions for easy interactions with Map
  """

  #Elixir.Map.update implementation is wird. When key doesn't exist it puts initial in key instead of fun(initial).
  def update(map, key, initial, fun) do
    value = Map.get(map, key, initial)
    value_updated = fun.(value)
    Map.put(map, key, value_updated)
  end

end
