defmodule Aecore.Channel.Updates.ChannelTransferUpdate do

  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffchainUpdate

  @type t :: %ChannelTransferUpdate{
          from: binary(),
          to: binary(),
          amount: non_neg_integer()
        }

  defstruct [:from, :to, :amount]

  def new(from, to, amount) do
    %ChannelTransferUpdate{
      from: from,
      to: to,
      amount: amount
    }
  end

  def decode_from_list([from, to, amount])
  do
    %ChannelTransferUpdate{
      from: from,
      to: to,
      amount: amount
    }
  end

  def encode_to_list(
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        })
  do
    [from, to, amount]
  end

  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        },
        %ChannelStateOnChain{})
  do
    try do
      updated_accounts =
        AccountStateTree.update(accounts, from, fn account ->
          account
          |> Account.apply_transfer!(nil, -amount)
          |> Account.apply_nonce!(account.nonce+1)
          |> ChannelOffchainUpdate.ensure_minimal_deposit_is_meet!(0)
        end)
        |>
        AccountStateTree.update(to, fn account ->
          Account.apply_transfer!(account, nil, amount)
        end)
      {:ok, %Chainstate{chainstate | accounts: updated_accounts}}
    catch
      {:error, _} = err ->
        err
    end
  end
end