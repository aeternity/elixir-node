defmodule Aecore.Chain.Genesis do
  @moduledoc """
  Module defining the Genesis block
  """

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{KeyBlock, Chainstate, KeyHeader}
  alias Aecore.Governance.GovernanceConstants, as: Governance
  alias Aecore.Governance.GenesisConstants, as: GenesisConstants
  alias Aeutil.Environment

  require Logger

  @spec hash() :: binary()
  def hash do
    KeyHeader.hash(header())
  end

  @spec block() :: KeyBlock.t()
  def block do
    header = header()
    %KeyBlock{header: header}
  end

  @spec populated_trees() :: Chainstate.t()
  def populated_trees do
    populated_trees(preset_accounts())
  end

  @spec populated_trees(list()) :: Chainstate.t()
  def populated_trees(accounts) do
    chainstate_init = Chainstate.create_chainstate_trees()
    miner = {GenesisConstants.miner(), Governance.coinbase_transaction_amount()}

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

  @spec preset_accounts() :: list()
  def preset_accounts do
    case read_presets() do
      {:error, reason} ->
        Logger.error("#{__MODULE__}: #{inspect(reason)}")
        []

      {:ok, json_data} ->
        decoded_data = Poison.decode!(json_data)
        Enum.map(decoded_data, fn {key, value} -> {Account.base58c_decode(key), value} end)
    end
  end

  @spec read_presets() :: {:ok, binary()} | {:error, reason :: atom()}
  def read_presets do
    preset_accounts_file =
      Path.join([
        Environment.get_env_or_core_priv_dir("ACCOUNTS_PATH", "genesis"),
        "accounts.json"
      ])

    case File.read(preset_accounts_file) do
      {:ok, _} = file -> file
      {:error, _} = error -> error
    end
  end

  @spec header() :: KeyHeader.t()
  def header do
    %KeyHeader{
      height: GenesisConstants.height(),
      prev_hash: GenesisConstants.prev_hash(),
      prev_key_hash: GenesisConstants.prev_key_hash(),
      root_hash: Chainstate.calculate_root_hash(populated_trees()),
      time: GenesisConstants.time(),
      nonce: GenesisConstants.nonce(),
      miner: GenesisConstants.miner(),
      beneficiary: GenesisConstants.beneficiary(),
      pow_evidence: GenesisConstants.evidence(),
      version: GenesisConstants.version(),
      target: GenesisConstants.target()
    }
  end
end
