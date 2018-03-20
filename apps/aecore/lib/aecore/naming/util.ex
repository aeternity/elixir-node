defmodule Aecore.Naming.Util do
  alias Aeutil.Hash

  @spec namehash(String.t()) :: binary()
  def namehash(name) do
    if name == "" do
      <<0::256>>
    else
      {label, remainder} = partition_name(name)
      Hash.hash(namehash(remainder) <> Hash.hash(label))
    end
  end

  @spec partition_name(String.t()) :: {String.t(), String.t()}
  defp partition_name(name) do
    [label | remainder] = String.split(name, ".")
    {label, Enum.join(remainder, ".")}
  end
end
