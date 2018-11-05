defmodule Aecore.Pow.Pow do
  @moduledoc """
  An abstraction layer for Proof of Work schemes that invokes the chosen algorithm based on the current environment variables
  """

  alias Aecore.Chain.Header

  @behaviour Aecore.Pow.PowAlgorithm

  @doc """
  Calls verify of appropriate module
  """
  @spec verify(Header.t()) :: boolean()
  def verify(%Header{} = header) do
    pow_module().verify(header)
  end

  @doc """
  Calls generate of appropriate module
  """
  @spec generate(Header.t()) :: {:ok, Header.t()} | {:error, atom()}
  def generate(%Header{} = header) do
    pow_module().generate(header)
  end

  defp pow_module, do: Application.get_env(:aecore, :pow_module)
end
