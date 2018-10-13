defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  use Aecore.Util.StateTrees, [:accounts, Aecore.Account.Account]

  alias Aecore.Account.Account
  alias Aecore.Chain.Identifier
  alias Aecore.Keys
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @typedoc "Accounts tree"
  @type accounts_state :: Trie.t()

  @spec get(accounts_state(), Keys.pubkey()) :: Account.t()
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      {:ok, account_state} ->
        {:ok, acc} = Account.rlp_decode(account_state)
        process_struct(acc, key, tree)

      :none ->
        Account.empty()
    end
  end

  @spec process_struct(Account.t(), binary(), accounts_state()) ::
          Account.t() | {:error, String.t()}
  def process_struct(%Account{} = deserialized_value, key, _tree) do
    id = Identifier.create_identity(key, :account)
    %Account{deserialized_value | id: id}
  end

  def process_struct(deserialized_value, _key, _tree) do
    {:error,
     "#{__MODULE__}: Invalid data type: #{deserialized_value.__struct__} but expected %Account{}"}
  end
end
