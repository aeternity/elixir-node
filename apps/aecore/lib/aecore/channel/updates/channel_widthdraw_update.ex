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
  @spec update_offchain_chainstate(Chainstate.t(), ChannelDepositUpdate.t(), non_neg_integer()) ::
          {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelWithdrawUpdate{
          to: to,
          amount: amount
        },
        channel_reserve
      ) do
    case AccountStateTree.safe_update(
           accounts,
           to,
           &widthdraw_from_account(&1, amount, channel_reserve)
         ) do
      {:ok, updated_accounts} ->
        {:ok, %Chainstate{chainstate | accounts: updated_accounts}}

      {:error, _} = err ->
        err
    end
  end

  @spec widthdraw_from_account(Account.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Account.t()} | error()
  defp widthdraw_from_account(account, amount, channel_reserve) do
    with {:ok, account1} <- Account.apply_transfer(account, nil, -amount),
         :ok <- ChannelOffChainUpdate.ensure_channel_reserve_is_met(account1, channel_reserve) do
      {:ok, account1}
    else
      {:error, _} = err ->
        err
    end
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
end
