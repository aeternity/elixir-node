defmodule Aecore.Channel.Updates.ChannelDepositUpdate do
  @moduledoc """
  State channel update implementing deposits in the state channel. This update can be included in ChannelOffchainTx.
  This update is used by ChannelDepositTx for transfering onchain tokens to the state channel.
  """

  alias Aecore.Channel.Updates.ChannelDepositUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  @behaviour ChannelOffChainUpdate

  @typedoc """
  Structure of the ChannelDepositUpdate type
  """
  @type t :: %ChannelDepositUpdate{
          from: binary(),
          amount: non_neg_integer()
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of ChannelDepositUpdate structure

  ## Parameters
  - from: the onchain account from which the deposit was made
  - amount: number of the tokens deposited into the state channel
  """
  defstruct [:from, :amount]

  @doc """
  Deserializes ChannelDepositUpdate. The serialization was changed in later versions of epoch.
  """
  @spec decode_from_list(list(binary())) :: ChannelDepositUpdate.t()
  def decode_from_list([from, from, amount]) do
    %ChannelDepositUpdate{
      from: from,
      amount: amount
    }
  end

  @doc """
  Serializes ChannelDepositUpdate. The serialization was changed in later versions of epoch.
  """
  @spec encode_to_list(ChannelDepositUpdate.t()) :: list(binary())
  def encode_to_list(%ChannelDepositUpdate{
        from: from,
        amount: amount
      }) do
    [from, from, amount]
  end

  @doc """
  Performs the deposit on the offchain chainstate. Returns an error if the deposit failed.
  """
  @spec update_offchain_chainstate(Chainstate.t(), ChannelDepositUpdate.t(), non_neg_integer()) ::
          {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(
        %Chainstate{
          accounts: accounts
        } = chainstate,
        %ChannelDepositUpdate{
          from: from,
          amount: amount
        },
        _channel_reserve
      ) do
    updated_accounts =
      AccountStateTree.update(accounts, from, fn account ->
        Account.apply_transfer!(account, nil, amount)
      end)

    {:ok, %Chainstate{chainstate | accounts: updated_accounts}}
  catch
    {:error, _} = err ->
      err
  end

  @spec half_signed_preprocess_check(ChannelDepositUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(%ChannelDepositUpdate{
          from: from,
        },
        %{
          foreign_pubkey: correct_from
        }) do
    cond do
      from != correct_from ->
        {:error, "#{__MODULE__}: Funds can only be deposited to the update initiator's account"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelDepositUpdate{}, _) do
    {:error, "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end
end
