defmodule Aecore.Channel.Updates.ChannelTransferUpdate do
  @moduledoc """
  State channel update implementing transfers in the state channel. This update can be included in ChannelOffchainTx.
  This update allows for transfering tokens between peers in the state channel(later for transfers to offchain contract accounts)..
  """

  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffChainUpdate

  @typedoc """
  Structure of the ChannelTransferUpdate type
  """
  @type t :: %ChannelTransferUpdate{
          from: binary(),
          to: binary(),
          amount: non_neg_integer()
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of ChannelTransferUpdate structure

  ## Parameters
  - from: the offchain account where the transfer originates
  - to: the offchain account which is the destination of the transfer
  - amount: number of the tokens transfered between the peers
  """
  defstruct [:from, :to, :amount]

  @doc """
  Creates an ChannelTransferUpdate
  """
  @spec new(binary(), binary(), non_neg_integer()) :: ChannelTransferUpdate.t()
  def new(from, to, amount) do
    %ChannelTransferUpdate{
      from: from,
      to: to,
      amount: amount
    }
  end

  @doc """
  Deserializes ChannelTransferUpdate.
  """
  @spec decode_from_list(list(binary())) :: ChannelTransferUpdate.t()
  def decode_from_list([from, to, amount]) do
    %ChannelTransferUpdate{
      from: from,
      to: to,
      amount: amount
    }
  end

  @doc """
  Serializes ChannelTransferUpdate.
  """
  @spec encode_to_list(ChannelTransferUpdate.t()) :: list(binary())
  def encode_to_list(
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        })
  do
    [from, to, amount]
  end

  @doc """
  Performs the transfer on the offchain chainstate. Returns an error if the transfer failed.
  """
  @spec update_offchain_chainstate(Chainstate.t(), ChannelDepositUpdate.t(), non_neg_integer()) :: {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        },
        channel_reserve)
  do
    updated_accounts1 =
      AccountStateTree.update(accounts, from, fn account ->
        account
        |> Account.apply_transfer!(nil, -amount)
        |> Account.apply_nonce!(account.nonce+1)
        |> ChannelOffChainUpdate.ensure_channel_reserve_is_meet!(channel_reserve)
      end)
    updated_accounts2 =
      AccountStateTree.update(updated_accounts1, to, fn account ->
        Account.apply_transfer!(account, nil, amount)
      end)
    {:ok, %Chainstate{chainstate | accounts: updated_accounts2}}
  catch
    {:error, _} = err ->
      err
  end

   @spec half_signed_preprocess_check(ChannelTransferUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(%ChannelTransferUpdate{
          from: from,
          to: to
        },
        %{
          our_pubkey: correct_to,
          foreign_pubkey: correct_from
        }) do
    cond do
      from != correct_from ->
        {:error, "#{__MODULE__}: Transfer must originate from the initiator of the update"}

      to != correct_to ->
        {:error, "#{__MODULE__}: Transfer must be to the peer responding to the update"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelTransferUpdate{}, _) do
    {:error, "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end
end
