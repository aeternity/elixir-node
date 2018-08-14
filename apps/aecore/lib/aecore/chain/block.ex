defmodule Aecore.Chain.Block do
  @moduledoc """
  Structure of the block
  """
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.Chainstate
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.BlockValidation
  alias Aecore.Governance.GovernanceConstants, as: Governance
  alias Aeutil.Genesis
  alias Aeutil.Serialization

  @type t :: %Block{
          header: Header.t(),
          txs: list(SignedTx.t())
        }
  # was changed to match current Epoch's block version
  @current_block_version Application.get_env(:aecore, :version)[:block]

  defstruct [:header, :txs]
  use ExConstructor

  @spec current_block_version() :: non_neg_integer()
  def current_block_version do
    @current_block_version
  end

  @spec genesis_header() :: Header.t()
  defp genesis_header do
    header = %{
      height: Governance.genesis_height(),
      prev_hash: Governance.genesis_prev_hash(),
      txs_hash: Governance.genesis_txs_hash(),
      root_hash: Chainstate.calculate_root_hash(genesis_populated_trees()),
      time: Governance.genesis_time(),
      nonce: Governance.genesis_nonce(),
      miner: Governance.genesis_miner(),
      pow_evidence: Governance.genesis_evidence(),
      version: Governance.genesis_version(),
      target: Governance.genesis_target()
    }

    struct(Header, header)
  end

  def genesis_hash do
    BlockValidation.block_header_hash(genesis_header())
  end

  @spec genesis_block() :: Block.t()
  def genesis_block do
    header = genesis_header()
    %Block{header: header, txs: []}
  end

  def genesis_populated_trees do
    genesis_populated_trees(Genesis.preset_accounts())
  end

  def genesis_populated_trees(accounts) do
    chainstate_init = Chainstate.create_chainstate_trees()
    miner = {Governance.genesis_miner(), Governance.coinbase_transaction_amount()}

    Enum.reduce([miner | accounts], chainstate_init, fn {pubkey, balance}, new_trees ->
      new_acounts =
        new_trees.accounts
        |> AccountStateTree.put(
          pubkey,
          Account.new(%{balance: balance, nonce: 0, pubkey: pubkey})
        )

      struct(new_trees, accounts: new_acounts)
    end)
  end

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), Block.t()) ::
          binary() | {:error, String.t()}
  def rlp_encode(tag, _version, %Block{} = block) do
    header_bin = Serialization.header_to_binary(block.header)

    txs =
      for tx <- block.txs do
        Serialization.rlp_encode(tx, :signedtx)
      end

    list = [
      tag,
      block.header.version,
      header_bin,
      txs
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Invalid block or header struct #{inspect(data)}"}
  end

  @spec rlp_decode(list()) :: Block.t() | {:error, String.t()}
  def rlp_decode([header_bin, txs]) do
    txs_list =
      for tx <- txs do
        Serialization.rlp_decode(tx)
      end

    case txs_list_valid?(txs_list) do
      true -> Block.new(%{header: Serialization.binary_to_header(header_bin), txs: txs_list})
      false -> {:error, "#{__MODULE__} : Illegal SignedTx's serialization"}
    end
  end

  def rlp_decode(data) do
    {:error, "#{__MODULE__} : Illegal block serialization: #{inspect(data)} "}
  end

  @spec txs_list_valid?(list()) :: boolean()
  defp txs_list_valid?(txs_list) do
    Enum.all?(txs_list, fn
      {:error, _reason} -> false
      %SignedTx{} -> true
    end)
  end
end
