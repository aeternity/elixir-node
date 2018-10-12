defmodule Aecore.Naming.NamingStateTree do
  @moduledoc """
  Top level naming state tree.
  """
  use Aecore.Util.StateTrees, [:naming, [Aecore.Naming.Name, Aecore.Naming.NameCommitment]]

  alias Aecore.Naming.{Name, NameCommitment}

  @typedoc "Namings tree"
  @type namings_state() :: Trie.t()

  @spec process_struct(Name.t() | NameCommitment.t(), binary(), namings_state()) ::
          Name.t() | NameCommitment.t() | {:error, String.t()}
  def process_struct(%Name{} = deserialized_value, key, _tree) do
    hash = Identifier.create_identity(key, :name)
    %Name{deserialized_value | hash: hash}
  end

  def process_struct(%NameCommitment{} = deserialized_value, key, _tree) do
    hash = Identifier.create_identity(key, :commitment)
    %NameCommitment{deserialized_value | hash: hash}
  end

  def process_struct(deserialized_value, _key, _tree) do
    {:error,
     "#{__MODULE__}: Invalid data type: #{deserialized_value.__struct__} but expected %NameCommitment{} or %Name{}"}
  end
end
