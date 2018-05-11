defmodule Aecore.Chain.Chainstate do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Naming
  alias Aeutil.Bits

  require Logger

  @type accounts :: AccountStateTree.accounts_state()
  @type oracles :: OracleStateTree.oracles_state()
  @type naming :: Naming.state()

  @type t :: %Chainstate{
          accounts: accounts(),
          oracles: oracles(),
          naming: naming()
        }

  defstruct [
    :accounts,
    :oracles,
    :naming
  ]

  @spec init :: Chainstate.t()
  def init do
    %Chainstate{
      :accounts => AccountStateTree.init_empty(),
      :oracles => OracleStateTree.init_empty(),
      :naming => Naming.init_empty()
    }
  end

  @spec calculate_and_validate_chain_state(list(), Chainstate.t(), non_neg_integer()) ::
          {:ok, Chainstate.t()} | {:error, String.t()}
  def calculate_and_validate_chain_state(txs, chainstate, block_height) do
    updated_chainstate =
      Enum.reduce_while(txs, chainstate, fn tx, chainstate ->
        case apply_transaction_on_state(chainstate, block_height, tx) do
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

  @spec apply_transaction_on_state(Chainstate.t(), non_neg_integer(), SignedTx.t()) ::
          Chainstate.t()
  def apply_transaction_on_state(chainstate, block_height, tx) do
    case SignedTx.validate(tx) do
      :ok ->
        SignedTx.process_chainstate(chainstate, block_height, tx)

      err ->
        err
    end
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
        case apply_transaction_on_state(chainstate, block_height, tx) do
          {:ok, updated_chainstate} ->
            {[tx | valid_txs_list], updated_chainstate}

          {:error, reason} ->
            Logger.error(reason)
            {valid_txs_list, updated_chainstate}
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
