defmodule Aecore.Naming.Structures.NameClaimTx do
  @moduledoc """
  Aecore structure of naming claim.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.NameClaimTx
  alias Aecore.Naming.Naming
  alias Aecore.Structures.Account
  alias Aecore.Naming.NameUtil

  require Logger

  @typedoc "Expected structure for the Claim Transaction"
  @type payload :: %{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameClaimTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %NameClaimTx{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @doc """
  Definition of Aecore NameClaimTx structure

  ## Parameters
  - name: name to be claimed
  - name_salt: salt that the name was pre-claimed with
  """
  defstruct [:name, :name_salt]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameClaimTx.t()
  def init(%{name: name, name_salt: name_salt} = _payload) do
    %NameClaimTx{name: name, name_salt: name_salt}
  end

  @doc """
  Checks name format
  """
  @spec is_valid?(NameClaimTx.t()) :: boolean()
  def is_valid?(%NameClaimTx{name: name, name_salt: name_salt}) do
    name_valid =
      case NameUtil.normalize_and_validate_name(name) do
        {:ok, _} -> true
        {:error, _} -> false
      end

    name_salt_valid = byte_size(name_salt) == Naming.get_name_salt_byte_size()
    name_valid && name_salt_valid
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          NameClaimTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %NameClaimTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming_state
      ) do
    sender_account_state = Map.get(accounts, sender, Account.empty())

    case preprocess_check(
           tx,
           sender_account_state,
           sender,
           fee,
           nonce,
           block_height,
           naming_state
         ) do
      :ok ->
        new_senderount_state =
          sender_account_state
          |> deduct_fee(fee)
          |> Account.transaction_out_nonce_update(nonce)

        updated_accounts_chainstate = Map.put(accounts, sender, new_senderount_state)
        account_naming = Map.get(naming_state, sender, Naming.empty())

        updated_naming_claims = [
          Naming.create_claim(block_height, tx.name, tx.name_salt) | account_naming.claims
        ]

        updated_naming_pre_claims =
          Enum.filter(account_naming.pre_claims, fn pre_claim ->
            pre_claim.commitment != Naming.create_commitment_hash(tx.name, tx.name_salt)
          end)

        updated_naming_chainstate =
          Map.put(naming_state, sender, %{
            account_naming
            | claims: updated_naming_claims,
              pre_claims: updated_naming_pre_claims
          })

        {updated_accounts_chainstate, updated_naming_chainstate}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the NameClaimTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          NameClaimTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check(tx, account_state, sender, fee, nonce, _block_height, naming_state) do
    account_naming = Map.get(naming_state, sender, Naming.empty())

    pre_claim =
      Enum.find(account_naming.pre_claims, fn pre_claim ->
        pre_claim.commitment == Naming.create_commitment_hash(tx.name, tx.name_salt)
      end)

    claims_for_name =
      naming_state
      |> Map.values()
      |> Enum.flat_map(fn name -> name.claims end)
      |> Enum.find(fn claim -> claim.name == tx.name end)

    naming_revoked = Map.get(naming_state, :revoked, [])

    revoked =
      Enum.find(naming_revoked, fn {revoked, _height} ->
        revoked == NameUtil.normalized_namehash!(tx.name)
      end)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      pre_claim == nil ->
        {:error, "Name has not been pre-claimed"}

      claims_for_name != nil ->
        {:error, "Name has aleady been claimed"}

      revoked != nil ->
        {:error, "Name has been revoked"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), tx_type_state()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end
end
