defmodule Aecore.Pow.Mock do
  @moduledoc """
  Provides a mock proof of work that allways succeeds generation and uses predefined integers as proof. In validation checks that integers are as expected
  """

  alias Aecore.Chain.Header

  @behaviour Aecore.Pow.PowAlgorithm

  @pow_length 42

  @doc """
  Proof of Work verification - check pow_evidence == proof()
  """
  @spec verify(Header.t()) :: boolean()
  def verify(%Header{pow_evidence: pow}) do
    pow == proof()
  end

  @doc """
  Returns a header with pow_evidence set to proof()
  """
  @spec generate(Header.t()) :: {:ok, Header.t()}
  def generate(%Header{} = header) do
    {:ok, %Header{header | pow_evidence: proof()}}
  end

  defp proof do
    Enum.to_list(1..@pow_length)
  end
end
