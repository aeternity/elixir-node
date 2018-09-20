defmodule Aecore.Pow.PowAlgorithm do
  alias Aecore.Chain.Header

  @type error :: {:error, String.t()}

  @doc """
  Proof of Work verification (with difficulty check)
  """
  @callback verify(Header.t()) :: boolean()

  @doc """
  Creates a pow_evidence. Returns a Header with pow_evidence field filld or error
  """
  @callback generate(Header.t()) :: {:ok, Header.t()} | error()
end
