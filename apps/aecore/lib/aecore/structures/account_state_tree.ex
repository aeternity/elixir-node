defmodule Aecore.Structures.AccountStateTree do
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization

  @type encoded_account_state :: binary()

  # abstract datatype
  @type tree :: tuple()

  @type hash :: binary()

  @spec init_empty() :: tuple()
  def init_empty() do
    :gb_merkle_trees.empty()
  end

  @spec put(tree(), Wallet.pubkey(), Account.t()) :: tree()
  def put(tree, key, value) do
    :gb_merkle_trees.enter(key, encode(value), tree)
  end

  @spec get(tree(), Wallet.pubkey()) :: Account.t()
  def get(tree, key) do
    ## TODO: In case of missing value for the given key
    decode(:gb_merkle_trees.lookup(key, tree))
  end

  @spec delete(tree(), Wallet.pubkey()) :: tree()
  def delete(tree, key) do
    :gb_merkle_trees.delete(key, tree)
  end

  @spec balance(tree()) :: tree()
  def balance(tree) do
    :gb_merkle_trees.balance(tree)
  end

  @spec root_hash(tree()) :: hash()
  def root_hash(tree) do
    :gb_merkle_trees.root_hash(tree)
  end

  @spec reduce(tree(), any(), fun()) :: any()
  def reduce(tree, acc, fun) do
    :gb_merkle_trees.foldr(fun, acc, tree)
  end

  @spec encode(Account.t()) :: binary()
  defp encode(%Account{} = account) do
    account
    |> Serialization.serialize_value()
    |> Msgpax.pack!()
  end

  @spec decode(encoded_account_state()) :: Account.t()
  defp decode(encoded_account_state) do
    {:ok, account_state} =
      encoded_account_state
      |> Msgpax.unpack()
      |> print("after unpack")
      |> Serialization.deserialize_value()

    Account.new(account_state)
  end

  defp print(term, title) do
    IO.inspect("#{title}: #{inspect(term)}")
    term
  end
end
