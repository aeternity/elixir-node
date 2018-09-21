defmodule Aecore.Pow.Pow do
  @moduledoc """
  A meta Proof of work alorithm that invokes proper allgorithm for current environment
  """

  alias Aecore.Chain.Header

  @behaviour Aecore.Pow.PowAlgorithm

  @doc """
  Calls verify of apropriate module
  """
  @spec verify(Header.t()) :: boolean()
  def verify(%Header{} = header) do
    pow_module().verify(header)
  end

  @doc """
  Calls generate of apropriate module
  """
  @spec generate(Header.t()) :: {:ok, Header.t()}
  def generate(%Header{} = header) do
    pow_module().generate(header)
  end

  defp pow_module, do: Application.get_env(:aecore, :pow_module)
end
