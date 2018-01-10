defmodule Aecore.Wallet.Worker do

  def has_wallet() do
    path =
      Application.get_env(:aecore, :aewallet)[:path]
      |> Path.join("*/")
      |> Path.wildcard()
    case path do
      []  -> false
      [_] -> true
    end
  end
end
