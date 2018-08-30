defmodule Aecore.Channel.Updates.ChannelDepositUpdate do

  alias Aecore.Channel.Updates.ChannelDepositUpdate
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffchainUpdate

  @type t :: %ChannelDepositUpdate{
          from: binary(),
          amount: non_neg_integer()
        }

  defstruct [:from, :amount]

  def decode_from_list([from, from, amount])
  do
    %ChannelDepositUpdate{
      from: from,
      amount: amount
    }
  end

  def encode_to_list(
        %ChannelDepositUpdate{
          from: from,
          amount: amount
        })
  do
    [from, from, amount]
  end

  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelDepositUpdate{
          from: from,
          amount: amount
        },
        _minimal_deposit)
  do
    try do
      updated_accounts =
        AccountStateTree.update(accounts, from, fn account ->
          account
          |> Account.apply_transfer!(nil, amount)
          #|> Account.apply_nonce!(from_account.nonce+1) #TODO: check if the nonce is being increased in epoch
        end)
      {:ok, %Chainstate{chainstate | accounts: updated_accounts}}
    catch
      {:error, _} = err ->
        err
    end
  end
end