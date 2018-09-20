defmodule Aecore.Pow.PowAlgorithm do
  @moduledoc """
  Behaviour that all proof of work algorithms have to follow
  """

  alias Aecore.Chain.Header

  @type error :: {:error, String.t()}

  @doc """
  Proof of Work verification (with difficulty check)
  """
  @callback verify(Header.t()) :: boolean()

  @doc """
  Creates a pow_evidence. Returns a Header with pow_evidence field filld or error.
  pow_evidence has to be a list of 42 integers.
  """
  @callback generate(Header.t()) :: {:ok, Header.t()} | error()
end
