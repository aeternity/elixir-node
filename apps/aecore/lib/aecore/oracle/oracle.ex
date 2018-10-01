defmodule Aecore.Oracle.Oracle do
  @moduledoc """
  Contains wrapping functions for working with oracles, data validation and TTL calculations.
  """

  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys
  alias Aecore.Oracle.{Oracle, OracleStateTree, OracleQuery}
  alias Aecore.Oracle.Tx.{OracleRegistrationTx, OracleQueryTx, OracleResponseTx, OracleExtendTx}
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.PatriciaMerkleTree

  @version 1

  require Logger

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Oracle transactions that include TTL field"
  @type oracle_txs_with_ttl :: OracleRegistrationTx.t() | OracleQueryTx.t() | OracleExtendTx.t()

  @typedoc "Expected TTL structure for the oracle transactions"
  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  @pubkey_size 33

  @typedoc "Structure of the Oracle type"
  @type t :: %Oracle{
          owner: Keys.pubkey(),
          query_format: binary(),
          response_format: binary(),
          query_fee: integer(),
          expires: integer()
        }

  defstruct [:owner, :query_format, :response_format, :query_fee, :expires]
  # use ExConstructor
  use Aecore.Util.Serializable

  @spec register(
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          ttl(),
          non_neg_integer()
        ) :: :ok | :error
  def register(
        query_format,
        response_format,
        query_fee,
        fee,
        ttl,
        tx_ttl \\ 0
      ) do
    payload = %{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }

    {pubkey, privkey} = Keys.keypair(:sign)

    tx_data =
      DataTx.init(
        OracleRegistrationTx,
        payload,
        pubkey,
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, privkey)
    Pool.add_transaction(tx)
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(
          Keys.pubkey(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          ttl(),
          ttl(),
          non_neg_integer()
        ) :: :ok | :error
  def query(oracle_address, query_data, query_fee, fee, query_ttl, response_ttl, tx_ttl \\ 0) do
    payload = %{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }

    {pubkey, privkey} = Keys.keypair(:sign)

    tx_data =
      DataTx.init(
        OracleQueryTx,
        payload,
        pubkey,
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} =
      SignedTx.sign_tx(
        tx_data,
        privkey
      )

    Pool.add_transaction(tx)
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), String.t(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def respond(query_id, response, fee, tx_ttl \\ 0) do
    payload = %OracleResponseTx{
      query_id: query_id,
      response: response
    }

    {pubkey, privkey} = Keys.keypair(:sign)

    tx_data = %DataTx{
      fee: fee,
      nonce: Chain.lowest_valid_nonce(),
      payload: payload,
      senders: [%Identifier{type: :oracle, value: pubkey}],
      ttl: tx_ttl,
      type: OracleResponseTx
    }

    {:ok, tx} = SignedTx.sign_tx(tx_data, privkey)
    Pool.add_transaction(tx)
  end

  @spec extend(ttl(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee, tx_ttl \\ 0) do
    payload = %OracleExtendTx{
      ttl: ttl
    }

    {pubkey, privkey} = Keys.keypair(:sign)

    tx_data = %DataTx{
      fee: fee,
      nonce: Chain.lowest_valid_nonce(),
      payload: payload,
      senders: [%Identifier{type: :oracle, value: pubkey}],
      ttl: tx_ttl,
      type: OracleExtendTx
    }

    {:ok, tx} = SignedTx.sign_tx(tx_data, privkey)
    Pool.add_transaction(tx)
  end

  @spec calculate_ttl(ttl(), non_neg_integer()) :: non_neg_integer()
  def calculate_ttl(%{ttl: ttl, type: type}, block_height_tx_included) do
    case type do
      :absolute ->
        ttl

      :relative ->
        ttl + block_height_tx_included
    end
  end

  @spec tx_ttl_is_valid?(oracle_txs_with_ttl() | SignedTx.t(), non_neg_integer()) :: boolean
  def tx_ttl_is_valid?(tx, block_height) do
    case tx do
      %OracleRegistrationTx{ttl: ttl} ->
        ttl_is_valid?(ttl, block_height)

      %OracleQueryTx{query_ttl: query_ttl, response_ttl: response_ttl} ->
        response_ttl_is_valid =
          case response_ttl do
            %{type: :absolute} ->
              Logger.error("#{__MODULE__}: Response TTL has to be relative")
              false

            %{type: :relative} ->
              ttl_is_valid?(response_ttl, block_height)
          end

        query_ttl_is_valid = ttl_is_valid?(query_ttl, block_height)

        response_ttl_is_valid && query_ttl_is_valid

      %OracleExtendTx{ttl: ttl} ->
        ttl > 0

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

  @spec remove_expired(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def remove_expired(chainstate, block_height) do
    OracleStateTree.prune(chainstate, block_height)
  end

  @spec refund_sender(OracleQuery.t(), AccountStateTree.accounts_state()) ::
          AccountStateTree.accounts_state()
  def refund_sender(
        %OracleQuery{
          sender_address: %Identifier{value: sender_address},
          has_response: has_response,
          fee: fee
        },
        accounts_state
      ) do
    if not has_response do
      AccountStateTree.update(accounts_state, sender_address, fn account ->
        Map.update!(account, :balance, &(&1 + fee))
      end)
    else
      accounts_state
    end
  end

  defp ttl_is_valid?(%{ttl: ttl, type: type}, block_height) do
    case type do
      :absolute ->
        ttl - block_height > 0

      :relative ->
        ttl > 0
    end
  end

  @spec get_registered_oracles :: map()
  def get_registered_oracles do
    oracle_tree = Chain.chain_state().oracles.oracle_tree
    keys = PatriciaMerkleTree.all_keys(oracle_tree)

    registered_oracles_key =
      Enum.reduce(keys, [], fn key, acc ->
        if byte_size(key) == @pubkey_size do
          [key | acc]
        else
          acc
        end
      end)

    Enum.reduce(registered_oracles_key, %{}, fn pub_key, acc ->
      Map.put(acc, pub_key, OracleStateTree.get_oracle(Chain.chain_state().oracles, pub_key))
    end)
  end

  @spec encode_to_list(Oracle.t()) :: list()
  def encode_to_list(%Oracle{} = oracle) do
    [
      :binary.encode_unsigned(@version),
      oracle.query_format,
      oracle.response_format,
      :binary.encode_unsigned(oracle.query_fee),
      :binary.encode_unsigned(oracle.expires)
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Oracle.t()} | {:error, reason()}
  def decode_from_list(@version, [query_format, response_format, query_fee, expires]) do
    {:ok,
     %Oracle{
       owner: %Identifier{type: :oracle},
       query_format: query_format,
       response_format: response_format,
       query_fee: :binary.decode_unsigned(query_fee),
       expires: :binary.decode_unsigned(expires)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
