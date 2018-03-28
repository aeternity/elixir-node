defmodule Aecore.Naming.Structures.UpdateTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.UpdateTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Naming.Util
  alias Aecore.Structures.Account

  require Logger

  @typedoc "Expected structure for the Update Transaction"
  @type payload :: %{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of UpdateTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the UpdateTx Transaction type"
  @type t :: %UpdateTx{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @doc """
  Definition of Aecore UpdateTx structure

  ## Parameters
  - hash: hash of name to be updated
  - expire_by: expiration block of name update
  - client_ttl: ttl for client use
  - pointers: pointers from name update
  """
  defstruct [:hash, :expire_by, :client_ttl, :pointers]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: UpdateTx.t()
  def init(%{
        hash: hash,
        expire_by: expire_by,
        client_ttl: client_ttl,
        pointers: pointers
      }) do
    %UpdateTx{hash: hash, expire_by: expire_by, client_ttl: client_ttl, pointers: pointers}
  end

  @doc """
  Checks name format
  """
  @spec is_valid?(UpdateTx.t()) :: boolean()
  def is_valid?(%UpdateTx{
        hash: _hash,
        expire_by: _expire_by,
        client_ttl: client_ttl,
        pointers: _pointers
      }) do
    # TODO check pointers format
    valid_pointers_format = true
    valid_client_ttl = client_ttl <= Naming.get_client_ttl_limit()
    valid_client_ttl && valid_pointers_format
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          UpdateTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %UpdateTx{} = tx,
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

        claim_to_update =
          Enum.find(account_naming.claims, fn claim ->
            tx.hash == Util.normalized_namehash!(claim.name)
          end)

        filtered_claims =
          Enum.filter(account_naming.claims, fn claim ->
            claim.name != claim_to_update.name
          end)

        updated_naming_claims = [
          Naming.create_claim(
            block_height,
            claim_to_update.name,
            claim_to_update.name_salt,
            tx.expire_by,
            tx.client_ttl,
            tx.pointers
          )
          | filtered_claims
        ]

        updated_naming_chainstate =
          Map.put(naming, sender, %{account_naming | claims: updated_naming_claims})

        {updated_accounts_chainstate, updated_naming_chainstate}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the UpdateTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          UpdateTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check(tx, account_state, sender, fee, nonce, block_height, naming) do
    account_naming = Map.get(naming, sender, Naming.empty())

    claimed =
      Enum.find(account_naming.claims, fn claim ->
        Util.normalized_namehash!(claim.name) == tx.hash
      end)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      claimed == nil ->
        {:error, "Name has not been claimed"}

      tx.expire_by <= block_height ->
        {:error, "Name expiration is now or in the past"}

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
