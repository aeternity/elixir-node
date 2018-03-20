defmodule Aecore.Naming.Structures.PreClaimTx do
  @moduledoc """
  Aecore structure of naming pre claim data.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.PreClaimTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Naming.Util
  alias Aeutil.Hash

  require Logger

  @type commitment_hash :: binary()

  @typedoc "Expected structure for the Pre Claim Transaction"
  @type payload :: %{
          commitment: commitment_hash()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of PreClaimTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %PreClaimTx{
          commitment: commitment_hash()
        }

  @doc """
  Definition of Aecore PreClaimTx structure

  ## Parameters
  - commitment: hash of the commitment for name claiming
  """
  defstruct [:commitment]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: PreClaimTx.t()
  def init(%{commitment: commitment} = _payload) do
    %PreClaimTx{commitment: commitment}
  end

  @doc """
  Checks nothing, pre claim transactions can't be validated
  """
  @spec is_valid?(PreClaimTx.t()) :: boolean()
  def is_valid?(%PreClaimTx{commitment: _commitment}) do
    true
  end

  @spec create_commitment_hash(String.t(), binary()) :: binary()
  def create_commitment_hash(name, name_salt) when is_binary(name_salt) do
    Hash.hash(Util.namehash(name) <> name_salt)
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          PreClaimTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), ChainState.naming()}
  def process_chainstate!(
        %PreClaimTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming
      ) do
    case preprocess_check(tx, accounts[sender], fee, nonce, block_height, naming) do
      :ok ->
        new_senderount_state =
          accounts[sender]
          |> deduct_fee(fee)

        updated_accounts_chainstate = Map.put(accounts, sender, new_senderount_state)
        account_naming = Map.get(naming, sender, Naming.empty())

        updated_naming_pre_claims = [
          Naming.create_pre_claim(block_height, tx.commitment) | account_naming.pre_claims
        ]

        updated_naming_chainstate =
          Map.put(naming, sender, %{account_naming | pre_claims: updated_naming_pre_claims})

        {updated_accounts_chainstate, updated_naming_chainstate}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the PreClaimTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          PreClaimTx.t(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.naming()
        ) :: :ok | {:error, reason()}
  def preprocess_check(_tx, account_state, fee, nonce, _block_height, _naming) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), ChainState.naming()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end
end
