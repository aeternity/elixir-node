defmodule Aecore.Contract.Sophia.SophiaAbi do

  def get_function_name_from_type_info(function_hash, type_info) do
    function_info =
      Enum.find(type_info, nil, fn function_info ->
        Enum.at(function_info, 0) == function_hash
      end)

    case function_info do
      nil ->
        {:error, :no_such_function}
      _ ->
        {:ok, Enum.at(function_info, 1)}
    end
  end

end
