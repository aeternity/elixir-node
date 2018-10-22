defmodule Aecore.Chain.Chainstate do
  @moduledoc """
  Module containing functionality for calculating the chainstate
  """

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Genesis}
  alias Aecore.Channel.ChannelStateTree
  alias Aecore.Contract.{CallStateTree, ContractStateTree}
  alias Aecore.Governance.{GenesisConstants, GovernanceConstants}
  alias Aecore.Keys
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Naming.NamingStateTree
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Tx.SignedTx
  alias Aeutil.{Bits, Hash}

  require Logger

  @protocol_version_field_size 64
  @protocol_version 15

  @doc """
  This is the canonical root hash of an empty Patricia merkle tree
  """
  @canonical_root_hash <<69, 176, 207, 194, 32, 206, 236, 91, 124, 28, 98, 196, 212, 25, 61, 56,
                         228, 235, 164, 142, 136, 21, 114, 156, 231, 95, 156, 10, 176, 228, 193,
                         192>>
  @genesis_miner GenesisConstants.miner()
  @state_hash_bytes 32

  @type accounts :: AccountStateTree.accounts_state()
  @type oracles :: OracleStateTree.oracles_state()
  @type naming :: NamingStateTree.namings_state()
  @type channels :: ChannelStateTree.channel_state()
  @type contracts :: ContractStateTree.contracts_state()
  @type calls :: CallStateTree.calls_state()
  @type chain_state_types :: :accounts | :oracles | :naming | :channels | :contracts | :calls

  @typedoc "Structure of the Chainstate"
  @type t :: %Chainstate{
          accounts: accounts(),
          oracles: oracles(),
          naming: naming(),
          channels: channels(),
          contracts: contracts(),
          calls: calls()
        }

  defstruct [
    :accounts,
    :oracles,
    :naming,
    :channels,
    :contracts,
    :calls
  ]

  @spec init :: Chainstate.t()
  def init do
    Genesis.populated_trees()
  end

  @spec calculate_and_validate_chain_state(
          list(),
          Chainstate.t(),
          non_neg_integer(),
          Keys.pubkey()
        ) :: {:ok, Chainstate.t()} | {:error, String.t()}
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
        {:ok, Oracle.remove_expired(new_chainstate, block_height)}

      error ->
        {:error, error}
    end
  end

  @spec create_chainstate_trees() :: Chainstate.t()
  def create_chainstate_trees do
    %Chainstate{
      :accounts => AccountStateTree.init_empty(),
      :oracles => OracleStateTree.init_empty(),
      :naming => NamingStateTree.init_empty(),
      :channels => ChannelStateTree.init_empty(),
      :contracts => ContractStateTree.init_empty(),
      :calls => CallStateTree.init_empty()
    }
  end

  defp calculate_chain_state_coinbase(txs, chainstate, block_height, miner) do
    case miner do
      @genesis_miner ->
        chainstate

      miner_pubkey ->
        accounts_state_with_coinbase =
          AccountStateTree.update(chainstate.accounts, miner_pubkey, fn acc ->
            Account.apply_transfer!(
              acc,
              block_height,
              GovernanceConstants.coinbase_transaction_amount() + Miner.calculate_total_fees(txs)
            )
          end)

        %{chainstate | accounts: accounts_state_with_coinbase}
    end
  end

  @spec apply_transaction_on_state(Chainstate.t(), non_neg_integer(), SignedTx.t()) ::
          Chainstate.t() | {:error, String.t()}
  def apply_transaction_on_state(chainstate, block_height, tx) do
    case SignedTx.validate(tx) do
      :ok ->
        SignedTx.check_apply_transaction(chainstate, block_height, tx)

      err ->
        err
    end
  end

  @doc """
  Calculates the root hash of a chainstate tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    [
      AccountStateTree.root_hash(chainstate.accounts),
      CallStateTree.root_hash(chainstate.calls),
      ChannelStateTree.root_hash(chainstate.channels),
      ContractStateTree.root_hash(chainstate.contracts),
      NamingStateTree.root_hash(chainstate.naming),
      OracleStateTree.root_hash(chainstate.oracles)
    ]
    |> Enum.reduce(<<@protocol_version::size(@protocol_version_field_size)>>, fn root_hash, acc ->
      acc <> pad_empty(root_hash)
    end)
    |> Hash.hash_blake2b()
  end

  defp pad_empty(@canonical_root_hash) do
    <<0::size(@state_hash_bytes)-unit(8)>>
  end

  defp pad_empty(root_hash_binary)
       when is_binary(root_hash_binary) and byte_size(root_hash_binary) === @state_hash_bytes do
    root_hash_binary
  end

  @doc """
  Filters the invalid transactions out of the given list
  """
  @spec get_valid_txs(list(), Chainstate.t(), non_neg_integer()) :: list()
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

  @spec base58c_encode(binary()) :: String.t()
  def base58c_encode(bin) do
    Bits.encode58c("bs", bin)
  end

  @spec base58c_decode(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode(<<"bs$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end
end
