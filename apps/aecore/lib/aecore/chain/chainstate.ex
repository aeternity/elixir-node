defmodule Aecore.Chain.Chainstate do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.NamingStateTree
  alias Aeutil.Bits
  alias Aecore.Oracle.Oracle
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet

  require Logger

  @type accounts :: AccountStateTree.accounts_state()
  @type oracles :: Oracle.t()
  @type naming :: NamingStateTree.namings_state()
  @type chain_state_types :: :accounts | :oracles | :naming | :none

  @type t :: %Chainstate{
          accounts: accounts,
          oracles: oracles,
          naming: naming
        }

  defstruct [
    :accounts,
    :oracles,
    :naming
  ]

  @spec init :: t()
  def init do
    %Chainstate{
      :accounts => AccountStateTree.init_empty(),
      :oracles => %{registered_oracles: %{}, interaction_objects: %{}},
      :naming => NamingStateTree.init_empty()
    }
  end

  @spec calculate_and_validate_chain_state(
          list(),
          t(),
          non_neg_integer(),
          Wallet.pubkey()
        ) :: {:ok, t()} | {:error, String.t()}
  def calculate_and_validate_chain_state(txs, chainstate, block_height, miner) do
    chainstate_with_coinbase =
      calculate_chain_state_coinbase(txs, chainstate, block_height, miner)

    updated_chainstate =
      Enum.reduce_while(txs, chainstate_with_coinbase, fn tx, chainstate_acc ->
        case apply_transaction_on_state(chainstate_acc, block_height, tx) do
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

  defp calculate_chain_state_coinbase(txs, chainstate, block_height, miner) do
    case miner do
      <<0::256>> ->
        chainstate

      miner_pubkey ->
        accounts_state_with_coinbase =
          AccountStateTree.update(chainstate.accounts, miner_pubkey, fn acc ->
            Account.apply_transfer!(
              acc,
              block_height,
              Miner.coinbase_transaction_amount() + Miner.calculate_total_fees(txs)
            )
          end)

        %{chainstate | accounts: accounts_state_with_coinbase}
    end
  end

  @spec apply_transaction_on_state(t(), non_neg_integer(), SignedTx.t()) ::
          t() | {:error, String.t()}
  def apply_transaction_on_state(chainstate, block_height, tx) do
    case SignedTx.validate(tx, block_height) do
      :ok ->
        SignedTx.process_chainstate(chainstate, block_height, tx)

      err ->
        err
    end
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(t()) :: binary()
  def calculate_root_hash(chainstate) do
    AccountStateTree.root_hash(chainstate.accounts)
  end

  @doc """
  Goes through all the transactions and only picks the valid ones
  """
  @spec get_valid_txs(list(), t(), non_neg_integer()) :: list()
  def get_valid_txs(txs_list, chainstate, block_height) do
    {txs_list, _} =
      List.foldl(txs_list, {[], chainstate}, fn tx, {valid_txs_list, chainstate} ->
        case apply_transaction_on_state(chainstate, block_height, tx) do
          {:ok, updated_chainstate} ->
            {[tx | valid_txs_list], updated_chainstate}

          {:error, reason} ->
            Logger.error(reason)
            {valid_txs_list, chainstate}
        end
      end)

    Enum.reverse(txs_list)
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
