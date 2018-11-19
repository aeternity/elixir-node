defmodule Aecore.Pow.Mock do
  @moduledoc """
  Provides a mock proof of work that always succeeds generation and uses predefined integers as proof. In validation checks that integers are as expected
  """

  alias Aecore.Chain.KeyHeader

  @behaviour Aecore.Pow.PowAlgorithm

  @pow_length 42

  @doc """
  Proof of Work verification - check pow_evidence == proof()
  """
  @spec verify(KeyHeader.t()) :: boolean()
  def verify(%KeyHeader{pow_evidence: pow}) do
    pow == proof()
  end

  @doc """
  Returns a header with pow_evidence set to proof()
  """
  @spec generate(KeyHeader.t()) :: {:ok, KeyHeader.t()}
  def generate(%KeyHeader{} = header) do
    {:ok, %KeyHeader{header | pow_evidence: proof()}}
  end

  defp proof do
    Enum.to_list(1..@pow_length)
  end
end
