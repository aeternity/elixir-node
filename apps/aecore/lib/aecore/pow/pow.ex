defmodule Aecore.Pow.Pow do
  @moduledoc """
  An abstraction layer for Proof of Work schemes that invokes the chosen algorithm based on the current environment variables
  """

  alias Aecore.Chain.KeyHeader

  @behaviour Aecore.Pow.PowAlgorithm

  @doc """
  Calls verify of appropriate module
  """
  @spec verify(KeyHeader.t()) :: boolean()
  def verify(%KeyHeader{} = header) do
    pow_module().verify(header)
  end

  @doc """
  Calls generate of appropriate module
  """
  @spec generate(KeyHeader.t()) :: {:ok, KeyHeader.t()} | {:error, atom()}
  def generate(%KeyHeader{} = header) do
    pow_module().generate(header)
  end

  defp pow_module, do: Application.get_env(:aecore, :pow_module)
end
