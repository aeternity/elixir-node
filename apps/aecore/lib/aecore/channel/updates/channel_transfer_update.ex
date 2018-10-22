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
      amount: :binary.decode_unsigned(amount)
    }
  end

  @doc """
  Serializes ChannelTransferUpdate.
  """
  @spec encode_to_list(ChannelTransferUpdate.t()) :: list(binary())
  def encode_to_list(%ChannelTransferUpdate{
        from: from,
        to: to,
        amount: amount
      }) do
    [from, to, :binary.encode_unsigned(amount)]
  end

  @doc """
  Performs the transfer on the offchain chainstate. Returns an error if the transfer failed.
  """
  @spec update_offchain_chainstate!(Chainstate.t(), ChannelTransferUpdate.t()) ::
          Chainstate.t() | no_return()
  def update_offchain_chainstate!(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        }
      ) do
    updated_accounts =
      accounts
      |> AccountStateTree.update(
        from,
        &update_initiator_account!(&1, amount)
      )
      |> AccountStateTree.update(
        to,
        &Account.apply_transfer!(&1, nil, amount)
      )

    %Chainstate{chainstate | accounts: updated_accounts}
  end

  @spec update_initiator_account!(Account.t(), non_neg_integer()) :: Account.t() | no_return()
  defp update_initiator_account!(account, amount) do
    account
    |> Account.apply_transfer!(nil, -amount)
    |> Account.apply_nonce!(account.nonce + 1)
  end

  @spec half_signed_preprocess_check(ChannelTransferUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(
        %ChannelTransferUpdate{
          from: from,
          to: to,
          amount: amount
        },
        %{
          our_pubkey: correct_to,
          foreign_pubkey: correct_from
        }
      ) do
    cond do
      amount <= 0 ->
        {:error, "#{__MODULE__}: Can't transfer zero or negative amount of tokens"}

      from != correct_from ->
        {:error,
         "#{__MODULE__}: Transfer must originate from the initiator of the update (#{
           inspect(correct_from)
         }), got #{inspect(from)}"}

      to != correct_to ->
        {:error,
         "#{__MODULE__}: Transfer must be to the peer responding to the update (#{
           inspect(correct_to)
         }), got #{inspect(to)}"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelTransferUpdate{}, _) do
    {:error,
     "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end

  @doc """
  Validates an update considering state before applying it to the provided chainstate.
  """
  @spec fully_signed_preprocess_check(
          Chainstate.t() | nil,
          ChannelTransferUpdate.t(),
          non_neg_integer()
        ) :: :ok | error()

  def fully_signed_preprocess_check(
        %Chainstate{accounts: accounts},
        %ChannelTransferUpdate{from: from, to: to, amount: amount},
        channel_reserve
      ) do
    %Account{balance: from_balance} = AccountStateTree.get(accounts, from)

    cond do
      !AccountStateTree.has_key?(accounts, from) ->
        {:error, "#{__MODULE__}: Transfer initiator is not a party of this channel"}

      !AccountStateTree.has_key?(accounts, to) ->
        {:error, "#{__MODULE__}: Transfer responder is not a party of this channel"}

      from_balance - amount < channel_reserve ->
        {:error,
         "#{__MODULE__}: Transfer initiator tried to transfer #{amount} tokens but can transfer at most #{
           from_balance - channel_reserve
         } tokens"}

      true ->
        :ok
    end
  end

  def fully_signed_preprocess_check(nil, %ChannelTransferUpdate{}, _channel_reserve) do
    {:error, "#{__MODULE__}: OffChain Chainstate must exist"}
  end
end
