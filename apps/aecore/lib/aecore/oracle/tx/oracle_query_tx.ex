defmodule Aecore.Oracle.Tx.OracleQueryTx do
  @moduledoc """
  Module defining the OracleQuery transaction
  """

  use Aecore.Tx.Transaction

  alias __MODULE__

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Keys
  alias Aecore.Oracle.{Oracle, OracleQuery, OracleStateTree}
  alias Aecore.Tx.DataTx
  alias Aeutil.{Bits, Hash, Serialization}

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @type id :: binary()

  @typedoc "Expected structure for the OracleQuery Transaction"
  @type payload :: %{
          oracle_address: Identifier.t(),
          query_data: String.t(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @typedoc "Structure of the OracleQuery Transaction type"
  @type t :: %OracleQueryTx{
          oracle_address: Identifier.t(),
          query_data: String.t(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.oracles()

  @nonce_size 256

  defstruct [
    :oracle_address,
    :query_data,
    :query_fee,
    :query_ttl,
    :response_ttl
  ]

  @spec get_chain_state_name() :: atom()
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: OracleQueryTx.t()
  def init(%{
        oracle_address: %Identifier{} = identified_oracle_address,
        query_data: query_data,
        query_fee: query_fee,
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }) do
    %OracleQueryTx{
      oracle_address: identified_oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }
  end

  def init(%{
        oracle_address: oracle_address,
        query_data: query_data,
        query_fee: query_fee,
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }) do
    identified_oracle_address = Identifier.create_identity(oracle_address, :oracle)

    %OracleQueryTx{
      oracle_address: identified_oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(OracleQueryTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %OracleQueryTx{
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          oracle_address: %Identifier{value: address} = oracle_address
        },
        %DataTx{senders: senders}
      ) do
    cond do
      !Oracle.ttl_is_valid?(query_ttl) ->
        {:error, "#{__MODULE__}: Invalid query ttl"}

      !Oracle.ttl_is_valid?(response_ttl) ->
        {:error, "#{__MODULE__}: Invalid response ttl"}

      !match?(%{type: :relative}, response_ttl) ->
        {:error, "#{__MODULE__}: Invalid ttl type"}

      !validate_identifier(oracle_address) ->
        {:error, "#{__MODULE__}: Invalid oracle identifier: #{inspect(oracle_address)}"}

      !Keys.key_size_valid?(address) ->
        {:error, "#{__MODULE__}: oracle_adddress size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @doc """
  Enters a query in the oracle state tree
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleQueryTx{
          query_fee: query_fee,
          oracle_address: %Identifier{value: oracle_address},
          query_data: query_data,
          query_ttl: query_ttl,
          response_ttl: %{ttl: response_ttl},
          query_fee: query_fee
        },
        %DataTx{nonce: nonce, senders: [%Identifier{value: sender}]}
      ) do
    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, query_fee * -1)
      end)

    query = %OracleQuery{
      sender_address: sender,
      sender_nonce: nonce,
      oracle_address: oracle_address,
      query: query_data,
      has_response: false,
      response: :undefined,
      expires: Oracle.calculate_absolute_ttl(query_ttl, block_height),
      response_ttl: response_ttl,
      fee: query_fee
    }

    new_oracle_tree = OracleStateTree.insert_query(oracles, query)

    {:ok, {updated_accounts_state, new_oracle_tree}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        oracles,
        block_height,
        %OracleQueryTx{
          query_fee: query_fee,
          oracle_address: %Identifier{value: oracle_address},
          query_data: query_data,
          query_fee: query_fee
        } = tx,
        %DataTx{senders: [%Identifier{value: sender}], fee: fee}
      ) do
    cond do
      AccountStateTree.get(accounts, sender).balance - fee - query_fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx)}"}

      !OracleStateTree.exists_oracle?(oracles, oracle_address) ->
        {:error, "#{__MODULE__}: No oracle registered with the address:
         #{inspect(oracle_address)}"}

      !is_binary(query_data) ->
        {:error, "#{__MODULE__}: Invalid query data: #{inspect(query_data)}"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(
        %DataTx{
          payload: %OracleQueryTx{
            query_fee: query_fee,
            oracle_address: %Identifier{value: oracle_address},
            query_ttl: query_ttl
          },
          fee: fee
        },
        oracles_tree,
        block_height
      ) do
    registered_oracle = OracleStateTree.get_oracle(oracles_tree, oracle_address)
    tx_query_fee_is_met = registered_oracle != :none && query_fee >= registered_oracle.query_fee

    ttl_fee = fee - GovernanceConstants.oracle_query_base_fee()

    tx_fee_is_met =
      case query_ttl do
        %{ttl: ttl, type: :relative} ->
          ttl_fee >= Oracle.calculate_minimum_fee(ttl)

        %{ttl: _ttl, type: :absolute} ->
          ttl_fee >=
            query_ttl
            |> Oracle.calculate_relative_ttl(block_height)
            |> Oracle.calculate_minimum_fee()
      end

    tx_fee_is_met && tx_query_fee_is_met
  end

  @spec id(Keys.pubkey(), non_neg_integer(), Identifier.t()) :: binary()
  def id(sender, nonce, oracle_address) do
    bin = sender <> <<nonce::@nonce_size>> <> oracle_address
    Hash.hash(bin)
  end

  @spec base58c_encode(binary()) :: binary()
  def base58c_encode(bin) do
    Bits.encode58c("qy", bin)
  end

  @spec base58c_decode(binary()) :: binary() | {:error, reason()}
  def base58c_decode(<<"qy$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec validate_identifier(Identifier.t()) :: boolean()
  defp validate_identifier(%Identifier{value: value} = id) do
    Identifier.create_identity(value, :oracle) == id
  end

  @spec encode_to_list(OracleQueryTx.t(), DataTx.t()) :: list() | {:error, reason()}
  def encode_to_list(
        %OracleQueryTx{
          oracle_address: oracle_address,
          query_data: query_data,
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          query_fee: query_fee
        },
        %DataTx{senders: [sender], nonce: nonce, fee: fee, ttl: ttl}
      ) do
    ttl_type_q = Serialization.encode_ttl_type(query_ttl)
    ttl_type_r = Serialization.encode_ttl_type(response_ttl)

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Identifier.encode_to_binary(oracle_address),
      query_data,
      :binary.encode_unsigned(query_fee),
      ttl_type_q,
      query_ttl.ttl,
      ttl_type_r,
      :binary.encode_unsigned(response_ttl.ttl),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        encoded_oracle_address,
        query_data,
        query_fee,
        encoded_query_ttl_type,
        query_ttl_value,
        encoded_response_ttl_type,
        response_ttl_value,
        fee,
        ttl
      ]) do
    query_ttl_type =
      encoded_query_ttl_type
      |> Serialization.decode_ttl_type()

    response_ttl_type =
      encoded_response_ttl_type
      |> Serialization.decode_ttl_type()

    case Identifier.decode_from_binary(encoded_oracle_address) do
      {:ok, oracle_address} ->
        payload = %{
          oracle_address: oracle_address,
          query_data: query_data,
          query_fee: :binary.decode_unsigned(query_fee),
          query_ttl: %{
            ttl: :binary.decode_unsigned(query_ttl_value),
            type: query_ttl_type
          },
          response_ttl: %{
            ttl: :binary.decode_unsigned(response_ttl_value),
            type: response_ttl_type
          }
        }

        DataTx.init_binary(
          OracleQueryTx,
          payload,
          [encoded_sender],
          :binary.decode_unsigned(fee),
          :binary.decode_unsigned(nonce),
          :binary.decode_unsigned(ttl)
        )

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
