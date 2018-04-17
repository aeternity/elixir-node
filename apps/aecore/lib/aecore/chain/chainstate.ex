defmodule Aecore.Chain.Chainstate do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aeutil.Bits
  alias Aecore.Oracle.Oracle

  require Logger

  @type t :: %Chainstate{
          accounts: AccountStateTree.accounts_state(),
          oracles: Oracle.t()
        }

  defstruct [
    :accounts,
    :oracles
  ]

  @spec init :: Chainstate.t()
  def init do
    %Chainstate{
      :accounts => AccountStateTree.init_empty(),
      :oracles => %{registered_oracles: %{}, interaction_objects: %{}}
    }
  end

  @spec calculate_and_validate_chain_state(list(), Chainstate.t(), non_neg_integer()) ::
          Chainstate.t()
  def calculate_and_validate_chain_state(txs, chainstate, block_height) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      case apply_transaction_on_state(tx, chainstate, block_height) do
        {:ok, updated_chainstate} ->
          updated_chainstate

        {:error, _reason} ->
          chainstate
      end
    end)
    |> Oracle.remove_expired_oracles(block_height)
    |> Oracle.remove_expired_interaction_objects(block_height)
  end

  @spec apply_transaction_on_state(SignedTx.t(), Chainstate.t(), non_neg_integer()) ::
          Chainstate.t()
  def apply_transaction_on_state(
        %{data: %{sender: nil, payload: %{receiver: receiver}} = data, signature: nil},
        %{accounts: accounts} = chainstate,
        _block_height
      ) do
    receiver_state = Account.get_account_state(accounts, receiver)
    new_receiver_state = SignedTx.reward(data, receiver_state)
    new_accounts_state = AccountStateTree.put(accounts, receiver, new_receiver_state)

    {:ok, Map.put(chainstate, :accounts, new_accounts_state)}
  end

  def apply_transaction_on_state(
        %{data: %{sender: sender, type: tx_type} = data} = tx,
        %{accounts: accounts} = chainstate,
        block_height
      )
      when is_binary(sender) do
    with :ok <- SignedTx.validate(tx),
         {:ok, child_tx} <- DataTx.validate(data),
         :ok <- tx_type.validate(child_tx),
         :ok <- DataTx.validate_sender(sender, chainstate),
         :ok <- DataTx.validate_nonce(accounts, data),
         :ok <- DataTx.preprocess_check(data, chainstate, block_height),
         {:ok, updated_chainstate} <- DataTx.process_chainstate(data, chainstate, block_height) do
      {:ok, updated_chainstate}
    else
      err -> err
    end
  end

  def apply_transaction_on_state(tx, _chainstate, _block_height) do
    {:error, "#{__MODULE__}: Invalid transaction: #{inspect(tx)}"}
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    AccountStateTree.root_hash(chainstate.accounts)
  end

  @doc """
  Goes through all the transactions and only picks the valid ones
  """
  @spec get_valid_txs(list(), Chainstate.t(), non_neg_integer()) :: list()
  def get_valid_txs(txs_list, chainstate, block_height) do
    {txs_list, _} =
      List.foldl(txs_list, {[], chainstate}, fn tx, {valid_txs_list, updated_chainstate} ->
        case apply_transaction_on_state(tx, chainstate, block_height) do
          {:ok, updated_chainstate} ->
            {[tx | valid_txs_list], updated_chainstate}

          {:error, reason} ->
            Logger.error(reason)
            {valid_txs_list, updated_chainstate}
        end
      end)

    Enum.reverse(txs_list)
  end

  @spec calculate_total_tokens(Chainstate.t()) :: non_neg_integer()
  def calculate_total_tokens(%{accounts: accounts_tree}) do
    AccountStateTree.reduce(accounts_tree, 0, fn {pub_key, _value}, acc ->
      acc + Account.balance(accounts_tree, pub_key)
    end)
  end

  def base58c_encode(bin) do
    Bits.encode58c("bs", bin)
  end

  def base58c_decode(<<"bs$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end
end
