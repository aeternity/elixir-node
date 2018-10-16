defmodule Aecore.Channel.Updates.ChannelWithdrawUpdate do
  @moduledoc """
  State channel update implementing withdraws in the state channel. This update can be included in ChannelOffchainTx.
  This update is used by ChannelWithdrawTx for transfering unlocking some of the state channel's tokens.
  """

  alias Aecore.Channel.Updates.ChannelWithdrawUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffChainUpdate

  @typedoc """
  Structure of the ChannelWithdrawUpdate type
  """
  @type t :: %ChannelWithdrawUpdate{
          to: binary(),
          amount: non_neg_integer()
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of ChannelWithdrawUpdate structure

  ## Parameters
  - to: the onchain account where the tokens will be returned
  - amount: number of the tokens withdrawn from the state channel
  """
  defstruct [:to, :amount]

  @doc """
  Deserializes ChannelWithdrawUpdate. The serialization was changed in later versions of epoch.
  """
  @spec decode_from_list(list(binary())) :: ChannelWithdrawUpdate.t()
  def decode_from_list([to, to, amount]) do
    %ChannelWithdrawUpdate{
      to: to,
      amount: :binary.decode_unsigned(amount)
    }
  end

  @doc """
  Serializes ChannelWithdrawUpdate. The serialization was changed in later versions of epoch.
  """
  @spec encode_to_list(ChannelWithdrawUpdate.t()) :: list(binary())
  def encode_to_list(%ChannelWithdrawUpdate{
        to: to,
        amount: amount
      }) do
    [to, to, :binary.encode_unsigned(amount)]
  end

  @doc """
  Performs the widthdraw on the offchain chainstate. Returns an error if the operation failed.
  """
  @spec update_offchain_chainstate!(Chainstate.t(), ChannelDepositUpdate.t()) ::
          Chainstate.t() | no_return()
  def update_offchain_chainstate!(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelWithdrawUpdate{
          to: to,
          amount: amount
        }
      ) do
    updated_accounts =
      AccountStateTree.update(
        accounts,
        to,
        &widthdraw_from_account!(&1, amount)
      )

    %Chainstate{chainstate | accounts: updated_accounts}
  end

  @spec widthdraw_from_account!(Account.t(), non_neg_integer()) :: Account.t() | no_return()
  defp widthdraw_from_account!(account, amount) do
    Account.apply_transfer!(account, nil, -amount)
  end

  @spec half_signed_preprocess_check(ChannelWithdrawUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(
        %ChannelWithdrawUpdate{
          to: to,
          amount: amount
        },
        %{
          foreign_pubkey: correct_to
        }
      ) do
    cond do
      amount <= 0 ->
        {:error, "#{__MODULE__}: Can't withdraw zero or negative amount of tokens"}

      to != correct_to ->
        {:error,
         "#{__MODULE__}: Funds can be only withdrawn from the update initiator's account (#{
           inspect(correct_to)
         }), got #{inspect(to)}"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelWithdrawUpdate{}, _) do
    {:error,
     "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end

  @doc """
  Validates an update considering state before applying it to the provided chainstate.
  """
  @spec fully_signed_preprocess_check(
          Chainstate.t() | nil,
          ChannelWithdrawUpdate.t(),
          non_neg_integer()
        ) :: :ok | error()

  def fully_signed_preprocess_check(
        %Chainstate{accounts: accounts},
        %ChannelWithdrawUpdate{to: to, amount: amount},
        channel_reserve
      ) do
    %Account{balance: to_balance} = AccountStateTree.get(accounts, to)

    cond do
      !AccountStateTree.has_key?(accounts, to) ->
        {:error, "#{__MODULE__}: Withdrawing account is not a party of this channel"}

      to_balance - amount < channel_reserve ->
        {:error,
         "#{__MODULE__}: Withdrawing party tried to withdraw #{amount} tokens but can withdraw at most #{
           to_balance - channel_reserve
         } tokens"}

      true ->
        :ok
    end
  end

  def fully_signed_preprocess_check(nil, %ChannelWithdrawUpdate{}, _channel_reserve) do
    {:error, "#{__MODULE__}: OffChain Chainstate must exist"}
  end
end
