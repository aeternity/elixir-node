defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.Account
  alias Aecore.Oracle.Oracle
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @typedoc "Structure of the accounts"
  @type accounts() :: %{Wallet.pubkey() => Account.t()}

  @type oracles :: %{
          registered_oracles: Oracle.registered_oracles(),
          interaction_objects: Oracle.interaction_objects()
        }

  @typedoc "Structure of the chainstate"
  @type chainstate() :: %{:accounts => accounts(), :oracles => oracles()}

  @spec calculate_and_validate_chain_state!(list(), chainstate(), non_neg_integer()) ::
          chainstate()
  def calculate_and_validate_chain_state!(txs, chainstate, block_height) do
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

  @spec apply_transaction_on_state(SignedTx.t(), chainstate(), integer()) :: chainstate()
  def apply_transaction_on_state(
        %{data: %{sender: nil, payload: %{receiver: receiver}} = data, signature: nil},
        %{accounts: accounts} = chainstate,
        block_height
      ) do
    receiver_state = Map.get(accounts, receiver, Account.empty())
    new_receiver_state = SignedTx.reward(data, block_height, receiver_state)

    new_accounts_state = Map.put(accounts, receiver, new_receiver_state)

    {:ok, Map.put(chainstate, :accounts, new_accounts_state)}
  end

  def apply_transaction_on_state(
        %{data: %{sender: sender, type: tx_type} = data} = tx,
        %{accounts: accounts} = chainstate,
        block_height
      )
      when not is_nil(sender) do
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

  def apply_transaction_on_state(_tx, _chainstate, _block_height) do
    {:error, "#{__MODULE__}: Invalid transaction"}
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_root_hash(chainstate()) :: binary()
  def calculate_root_hash(chainstate) do
    merkle_tree_data =
      for {account, data} <- chainstate.accounts do
        {account, Serialization.pack_binary(data)}
      end

    if Enum.empty?(merkle_tree_data) do
      <<0::256>>
    else
      merkle_tree =
        List.foldl(merkle_tree_data, :gb_merkle_trees.empty(), fn node, merkle_tree ->
          :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
        end)

      :gb_merkle_trees.root_hash(merkle_tree)
    end
  end

  def filter_invalid_txs(txs_list, chainstate, block_height) do
    List.foldl(txs_list, [], fn tx, valid_txs_list ->
      case apply_transaction_on_state(tx, chainstate, block_height) do
        {:ok, _updated_chainstate} ->
          valid_txs_list ++ [tx]

        {:error, reason} ->
          Logger.error(reason)
          valid_txs_list
      end
    end)
  end

  @spec calculate_total_tokens(chainstate()) :: non_neg_integer()
  def calculate_total_tokens(%{accounts: accounts}) do
    Enum.reduce(accounts, 0, fn {_account, state}, acc ->
      acc + state.balance
    end)
  end

  @spec update_chain_state_locked(chainstate(), Header.t()) :: chainstate()
  def update_chain_state_locked(%{accounts: accounts} = chainstate, header) do
    updated_accounts =
      Enum.reduce(accounts, %{}, fn {address, state}, acc ->
        Map.put(acc, address, Account.update_locked(state, header))
      end)

    Map.put(chainstate, :accounts, updated_accounts)
  end

  def base58c_encode(bin) do
    Bits.encode58c("bs", bin)
  end

  def base58c_decode(<<"bs$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end
end
