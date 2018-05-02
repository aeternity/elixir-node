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
  alias Aecore.Account.Tx.SpendTx
  alias Aeutil.Serialization

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
          {:ok, Chainstate.t()} | {:error, String.t()}
  def calculate_and_validate_chain_state(txs, chainstate, block_height) do
    updated_chainstate =
      Enum.reduce_while(txs, chainstate, fn tx, chainstate ->
        case apply_transaction_on_state(tx, chainstate, block_height) do
          {:ok, updated_chainstate} ->
            {:cont, updated_chainstate}

          {:error, reason} ->
            {:halt, reason}
        end
      end)

    case updated_chainstate do
      %Chainstate{} = new_chainstate ->
        {:ok,
         new_chainstate
         |> Oracle.remove_expired_oracles(block_height)
         |> Oracle.remove_expired_interaction_objects(block_height)}

      error ->
        {:error, error}
    end
  end

  @spec apply_transaction_on_state(SignedTx.t(), Chainstate.t(), non_neg_integer()) ::
          Chainstate.t()
  def apply_transaction_on_state(
        %{data: %{sender: nil, payload: %{receiver: receiver}} = data, signature: nil},
        %{accounts: accounts} = chainstate,
        block_height
      ) do
    receiver_state = Account.get_account_state(accounts, receiver)
    new_receiver_state = SignedTx.reward(data, receiver_state)
    updated_receiver_state = %{new_receiver_state | last_updated: block_height}

    new_accounts_state =
      AccountStateTree.put(chainstate.accounts, data.payload.receiver, updated_receiver_state)

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
         new_chainstate = apply_last_updated(data, chainstate, block_height),
         :ok <- tx_type.validate(child_tx),
         :ok <- DataTx.validate_sender(sender, new_chainstate),
         :ok <- DataTx.validate_nonce(accounts, data),
         :ok <- DataTx.preprocess_check(data, new_chainstate, block_height),
         {:ok, updated_chainstate} <-
           DataTx.process_chainstate(data, new_chainstate, block_height) do
      {:ok, updated_chainstate}
    else
      err -> err
    end
  end

  def apply_transaction_on_state(tx, _chainstate, _block_height) do
    {:error, "#{__MODULE__}: Invalid transaction: #{inspect(tx)}"}
  end

  def apply_last_updated(
        %{payload: child_tx, sender: sender},
        chainstate,
        block_height
      ) do
    updated_accounts_state_tree =
      child_tx
      |> case do
        %SpendTx{} ->
          chainstate.accounts
          |> Account.last_updated(child_tx.receiver, block_height)

        _ ->
          chainstate.accounts
      end
      |> Account.last_updated(sender, block_height)

    %{chainstate | accounts: updated_accounts_state_tree}
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

  @spec rlp_encode(Chainstate.t(), Wallet.pubkey()) :: atom()
  def rlp_encode(%Chainstate{accounts: accounts}, pkey) do
    account_info = Account.get_account_state(accounts, pkey)

    [
      type_to_tag(Account),
      get_version(Account),
      pkey,
      account_info.nonce,
      account_info.last_updated,
      account_info.balance
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(_) do
    {:error, "Invalid account chainstate structure"}
  end

  @spec rlp_decode(binary()) :: binary() | atom()
  def rlp_decode(values) when is_binary(values) do
    Account.rlp_decode(values)
  end

  # def rlp_decode(values) when is_binary(values) do
  #     [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
  #     tag = Serialization.transform_item(tag_bin, :int)
  #     ver = Serialization.transform_item(ver_bin, :int)

  #     case tag_to_type(tag) do
  #       Account ->
  #         [pkey, nonce, height, balance] = rest_data

  #         [
  #           pkey,
  #           Serialization.transform_item(nonce, :int),
  #           Serialization.transform_item(height, :int),
  #           Serialization.transform_item(balance, :int)
  #         ]

  #         {:ok,
  #          %Account{
  #            balance: Serialization.transform_item(balance, :int),
  #            last_updated: Serialization.transform_item(height, :int),
  #            nonce: Serialization.transform_item(nonce, :int)
  #          }}

  #       _ ->
  #         {:error, :invalid_serialization}
  #     end
  #   end
  def rlp_decode(:none) do
    :none
  end

  def rlp_decode(_) do
    :invalid_serialization
  end

  defp type_to_tag(Account), do: 10
  defp tag_to_type(10), do: Account
  defp get_version(Account), do: 1
end
