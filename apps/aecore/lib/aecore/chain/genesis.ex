defmodule Aecore.Chain.Genesis do
  @moduledoc """
  Module defining the Genesis block
  """

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Block, Chainstate, Header}
  alias Aecore.Governance.GovernanceConstants, as: Governance
  alias Aecore.Governance.GenesisConstants, as: GenesisConstants

  require Logger

  @dir Application.app_dir(:aecore, "priv") <> Application.get_env(:aecore, :account_path)[:path]

  @spec hash() :: binary()
  def hash do
    Header.hash(header())
  end

  @spec block() :: Block.t()
  def block do
    header = header()
    %Block{header: header, txs: []}
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
    preset_accounts_file = Path.join([@dir, "accounts.json"])

    case File.read(preset_accounts_file) do
      {:ok, _} = file -> file
      {:error, _} = error -> error
    end
  end

  @spec header() :: Header.t()
  defp header do
    header = %{
      height: GenesisConstants.height(),
      prev_hash: GenesisConstants.prev_hash(),
      txs_hash: GenesisConstants.txs_hash(),
      root_hash: Chainstate.calculate_root_hash(populated_trees()),
      time: GenesisConstants.time(),
      nonce: GenesisConstants.nonce(),
      miner: GenesisConstants.miner(),
      pow_evidence: GenesisConstants.evidence(),
      version: GenesisConstants.version(),
      target: GenesisConstants.target()
    }

    struct(Header, header)
  end
end
