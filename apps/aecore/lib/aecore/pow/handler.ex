defmodule Aecore.Pow.Handler do
  @moduledoc """
  Handles the Prove of Work. Gets the PoW handler from config if
  no pow was found - hashcash will be set as default
  """
  require Logger

  alias Aecore.Pow.Cuckoo
  alias Aecore.Pow.Hashcash

  @spec generate(map()) :: {:ok, map()}
  def generate(header), do:  handler.generate(header)

  @spec verify(map()) :: boolean()
  def verify(data), do: handler.verify(data)

  @spec verify(map(), integer(), integer(), integer()) :: boolean()
  def verify(data, nonce, soln, difficulty) do
    handler.verify(data, nonce, soln, difficulty)
  end

  defp handler() do
    handler(Application.get_env(:aecore, :pow)[:default_pow])
  end

  defp handler(:cuckoo), do:  Cuckoo
  defp handler(:hashcash), do: Hashcash
  defp handler(_), do: Hashcash

end
