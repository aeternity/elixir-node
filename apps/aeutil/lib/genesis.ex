defmodule Aeutil.Genesis do
  @moduledoc """
  Module for genesis block options
  """
  alias Aecore.Account.Account, as: Account
  @dir Application.get_env(:aecore, :account_path)[:path]

  @spec preset_accounts() :: list()
  def preset_accounts do
    case read_presets() do
      {:error, reason} ->
        {:error, reason}

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
      {:error, reason} -> {:error, reason}
    end
  end
end
