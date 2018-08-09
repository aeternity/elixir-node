defmodule Aecore.Oracle.Oracle do
  @moduledoc """
  Contains wrapping functions for working with oracles, data validation and TTL calculations.
  """

  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys.Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.Chainstate
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aecore.Chain.Identifier

  require Logger

  @type oracle_txs_with_ttl :: OracleRegistrationTx.t() | OracleQueryTx.t() | OracleExtendTx.t()

  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  @pubkey_size 33

  @spec register(
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          ttl(),
          non_neg_integer()
        ) :: :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl, tx_ttl \\ 0) do
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
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(
          Wallet.pubkey(),
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

    tx_data =
      DataTx.init(
        OracleQueryTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} =
      SignedTx.sign_tx(
        tx_data,
        Wallet.get_public_key(),
        Wallet.get_private_key()
      )

    Pool.add_transaction(tx)
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), String.t(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def respond(query_id, response, fee, tx_ttl \\ 0) do
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
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec extend(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee, tx_ttl \\ 0) do
    payload = %{
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleExtendTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
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

  @spec tx_ttl_is_valid?(oracle_txs_with_ttl() | SignedTx.t(), non_neg_integer()) :: boolean
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

  @spec remove_expired(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def remove_expired(chainstate, block_height) do
    OracleStateTree.prune(chainstate, block_height)
  end

  @spec refund_sender(map(), AccountStateTree.accounts_state()) ::
          AccountStateTree.accounts_state()
  def refund_sender(query, accounts_state) do
    if not query.has_response do
      AccountStateTree.update(accounts_state, query.sender_address.value, fn account ->
        Map.update!(account, :balance, &(&1 + query.fee))
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

  @spec rlp_encode(
          non_neg_integer(),
          non_neg_integer(),
          map(),
          :oracle | :oracle_query
        ) :: binary()
  def rlp_encode(tag, version, %{} = oracle, :oracle) do
    list = [
      tag,
      version,
      oracle.query_format,
      oracle.response_format,
      oracle.query_fee,
      oracle.expires
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(tag, version, %{} = oracle_query, :oracle_query) do
    has_response =
      case oracle_query.has_response do
        true -> 1
        false -> 0
      end

    response =
      case oracle_query.response do
        :undefined -> Parser.to_string(:undefined)
        %DataTx{type: OracleResponseTx} = data -> data
        _ -> oracle_query.response
      end

    {:ok, encoded_sender} = Identifier.encode_data(oracle_query.sender_address)
    {:ok, encoded_oracle_owner} = Identifier.encode_data(oracle_query.oracle_address)

    list = [
      tag,
      version,
      encoded_sender,
      oracle_query.sender_nonce,
      encoded_oracle_owner,
      oracle_query.query,
      has_response,
      response,
      oracle_query.expires,
      oracle_query.response_ttl,
      oracle_query.fee
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Invalid Oracle struct #{inspect(data)}"}
  end

  @spec rlp_decode(list(), :registered_oracle | :interaction_object) ::
          {:ok, map()} | {:error, String.t()}
  def rlp_decode(
        [query_format, response_format, query_fee, expires],
        :oracle
      ) do
    {:ok,
     %{
       owner: %Identifier{type: :oracle},
       query_format: query_format,
       response_format: response_format,
       query_fee: Serialization.transform_item(query_fee, :int),
       expires: Serialization.transform_item(expires, :int)
     }}
  end

  def rlp_decode(
        [
          sender_address,
          sender_nonce,
          oracle_address,
          query,
          has_response,
          response,
          expires,
          response_ttl,
          fee
        ],
        :oracle_query
      ) do
    has_response =
      case Serialization.transform_item(has_response, :int) do
        1 -> true
        0 -> false
      end

    {:ok, decoded_sender_address} = Identifier.decode_data(sender_address)
    {:ok, decoded_orc_owner} = Identifier.decode_data(oracle_address)

    new_response =
      case response do
        "undefined" -> String.to_atom(response)
        _ -> response
      end

    {:ok,
     %{
       expires: Serialization.transform_item(expires, :int),
       fee: Serialization.transform_item(fee, :int),
       has_response: has_response,
       oracle_address: decoded_orc_owner,
       query: query,
       response: new_response,
       response_ttl: Serialization.transform_item(response_ttl, :int),
       sender_address: decoded_sender_address,
       sender_nonce: Serialization.transform_item(sender_nonce, :int)
     }}
  end

  def rlp_decode(_) do
    {:error,
     "#{__MODULE__}Illegal Registered oracle state / Oracle interaction object serialization"}
  end
end
