defmodule Aecore.Channel.Updates.ChannelWithdrawUpdate do

  alias Aecore.Channel.Updates.ChannelWithdrawUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffchainUpdate

  @type t :: %ChannelWithdrawUpdate{
          to: binary(),
          amount: non_neg_integer()
        }

  defstruct [:to, :amount]

  def decode_from_list([to, to, amount])
  do
    %ChannelWithdrawUpdate{
      to: to,
      amount: amount
    }
  end

  def encode_to_list(
        %ChannelWithdrawUpdate{
          to: to,
          amount: amount
        })
  do
    [to, to, amount]
  end

  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelWithdrawUpdate{
          to: to,
          amount: amount
        },
        channel_reserve)
  do
    try do
      updated_accounts =
        AccountStateTree.update(accounts, to, fn account ->
          account
          |> Account.apply_transfer!(nil, -amount)
          #|> Account.apply_nonce!(from_account.nonce+1) #TODO: check if the nonce is being increased in epoch
          |> ChannelOffchainUpdate.ensure_channel_reserve_is_meet!(channel_reserve)
        end)
      {:ok, %Chainstate{chainstate | accounts: updated_accounts}}
    catch
      {:error, _} = err ->
        err
    end
  end
end