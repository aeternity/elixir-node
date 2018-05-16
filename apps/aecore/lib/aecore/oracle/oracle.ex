defmodule Aecore.Oracle.Oracle do
  @moduledoc """
  Contains wrapping functions for working with oracles, data validation and TTL calculations.
  """

  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account
  alias ExJsonSchema.Schema, as: JsonSchema
  alias ExJsonSchema.Validator, as: JsonValidator
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

  require Logger

  @type oracle_txs_with_ttl :: OracleRegistrationTx.t() | OracleQueryTx.t() | OracleExtendTx.t()

  @type json_schema :: map()
  @type json :: any()
  @oracles_fields [:registered_oracles, :interaction_objects]

  @type registered_oracles :: %{
          Wallet.pubkey() => %{
            tx: OracleRegistrationTx.t(),
            height_included: non_neg_integer()
          }
        }

  @type interaction_objects :: %{
          OracleQueryTx.id() => %{
            query: OracleQueryTx.t(),
            response: OracleResponseTx.t(),
            query_height_included: non_neg_integer(),
            response_height_included: non_neg_integer()
          }
        }

  @type t :: %{
          registered_oracles: registered_oracles(),
          interaction_objects: interaction_objects()
        }

  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  defstruct @oracles_fields

  def oracles_fields, do: @oracles_fields

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  a fee that should be paid by queries and a TTL.
  """
  @spec register(json_schema(), json_schema(), non_neg_integer(), non_neg_integer(), ttl()) ::
          :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl) do
    payload = %{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleRegistrationTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(Account.pubkey(), json(), non_neg_integer(), non_neg_integer(), ttl(), ttl()) ::
          :ok | :error
  def query(oracle_address, query_data, query_fee, fee, query_ttl, response_ttl) do
    payload = %{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }

    tx_data =
      DataTx.init(
        OracleQueryTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), non_neg_integer()) :: :ok | :error
  def respond(query_id, response, fee) do
    payload = %{
      query_id: query_id,
      response: response
    }

    tx_data =
      DataTx.init(
        OracleResponseTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec extend(non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee) do
    payload = %{
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleExtendTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec data_valid?(map(), map()) :: true | false
  def data_valid?(format, data) do
    schema = JsonSchema.resolve(format)

    case JsonValidator.validate(schema, data) do
      :ok ->
        true

      {:error, [{message, _}]} ->
        Logger.error(fn -> "#{__MODULE__}: " <> message end)
        false
    end
  end

  @spec calculate_absolute_ttl(ttl(), non_neg_integer()) :: non_neg_integer()
  def calculate_absolute_ttl(%{ttl: ttl, type: type}, block_height_tx_included) do
    case type do
      :absolute ->
        ttl

      :relative ->
        ttl + block_height_tx_included
    end
  end

  @spec calculate_relative_ttl(%{ttl: non_neg_integer(), type: :absolute}, non_neg_integer()) ::
          non_neg_integer()
  def calculate_relative_ttl(%{ttl: ttl, type: :absolute}, block_height) do
    ttl - block_height
  end

  @spec tx_ttl_is_valid?(oracle_txs_with_ttl(), non_neg_integer()) :: boolean
  def tx_ttl_is_valid?(tx, block_height) do
    case tx do
      %OracleRegistrationTx{} ->
        ttl_is_valid?(tx.ttl, block_height)

      %OracleQueryTx{} ->
        response_ttl_is_valid =
          case tx.response_ttl do
            %{type: :absolute} ->
              Logger.error("#{__MODULE__}: Response TTL has to be relative")
              false

            %{type: :relative} ->
              ttl_is_valid?(tx.response_ttl, block_height)
          end

        query_ttl_is_valid = ttl_is_valid?(tx.query_ttl, block_height)

        response_ttl_is_valid && query_ttl_is_valid

      %OracleExtendTx{} ->
        tx.ttl > 0

      _ ->
        true
    end
  end

  @spec ttl_is_valid?(ttl()) :: boolean()
  def ttl_is_valid?(ttl) do
    case ttl do
      %{ttl: ttl, type: :absolute} ->
        ttl > 0

      %{ttl: ttl, type: :relative} ->
        ttl > 0

      _ ->
        Logger.error("#{__MODULE__}: Invalid TTL definition")
        false
    end
  end

  def remove_expired_oracles(chainstate, block_height) do
    chainstate.oracles
    |> OracleStateTree.get_registered_oracles()
    |> Enum.reduce(chainstate, fn {address,
                                   %{
                                     expires: expiry_height
                                   }},
                                  acc ->
      if expiry_height <= block_height do
        updated_oracles = OracleStateTree.delete_registered_oracle(acc.oracles, address)
        %{acc | oracles: updated_oracles}
      else
        acc
      end
    end)
  end

  def remove_expired_interaction_objects(chainstate, block_height) do
    chainstate.oracles
    |> OracleStateTree.get_interaction_objects()
    |> Enum.reduce(chainstate, fn {query_id,
                                   %{
                                     sender_address: sender_address,
                                     has_response: has_response,
                                     expires: expires,
                                     fee: fee
                                   }},
                                  acc ->
      if expires <= block_height do
        new_oracles_state =
          acc.oracles
          |> OracleStateTree.delete_interaction_object(query_id)

        new_chainstate = %{acc | oracles: new_oracles_state}

        if has_response do
          new_chainstate
        else
          new_accounts_state =
            new_chainstate.accounts
            |> AccountStateTree.update(sender_address, fn account ->
              Account.apply_transfer!(account, block_height, fee)
            end)

          %{new_chainstate | accounts: new_accounts_state}
        end
      else
        acc
      end
    end)
  end

  defp ttl_is_valid?(%{ttl: ttl, type: type}, block_height) do
    case type do
      :absolute ->
        ttl - block_height > 0

      :relative ->
        ttl > 0
    end
  end
end
