defmodule Aecore.Naming.Structures.ClaimTx do
  @moduledoc """
  Aecore structure of naming claim.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.ClaimTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Structures.Account
  alias Aecore.Naming.Util

  require Logger

  @typedoc "Expected structure for the Claim Transaction"
  @type payload :: %{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of ClaimTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %ClaimTx{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @doc """
  Definition of Aecore ClaimTx structure

  ## Parameters
  - name: name to be claimed
  - name_salt: salt that the name was pre-claimed with
  """
  defstruct [:name, :name_salt]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: ClaimTx.t()
  def init(%{name: name, name_salt: name_salt} = _payload) do
    %ClaimTx{name: name, name_salt: name_salt}
  end

  @doc """
  Checks name format
  """
  @spec is_valid?(ClaimTx.t()) :: boolean()
  def is_valid?(%ClaimTx{name: name, name_salt: name_salt}) do
    name_valid =
      case Util.normalize_and_validate_name(name) do
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
          ClaimTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %ClaimTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming
      ) do
    case preprocess_check(tx, accounts[sender], sender, fee, nonce, block_height, naming) do
      :ok ->
        new_senderount_state =
          accounts[sender]
          |> deduct_fee(fee)
          |> Account.transaction_out_nonce_update(nonce)

        updated_accounts_chainstate = Map.put(accounts, sender, new_senderount_state)
        account_naming = Map.get(naming, sender, Naming.empty())

        updated_naming_claims = [
          Naming.create_claim(block_height, tx.name, tx.name_salt) | account_naming.claims
        ]

        updated_naming_pre_claims =
          Enum.filter(account_naming.pre_claims, fn pre_claim ->
            pre_claim.commitment != Naming.create_commitment_hash(tx.name, tx.name_salt)
          end)

        updated_naming_chainstate =
          Map.put(naming, sender, %{
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
  Checks whether all the data is valid according to the ClaimTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ClaimTx.t(),
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

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      pre_claim == nil ->
        {:error, "Name has not been pre-claimed"}

      claims_for_name != nil ->
        {:error, "Name has aleady been claimed"}

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
