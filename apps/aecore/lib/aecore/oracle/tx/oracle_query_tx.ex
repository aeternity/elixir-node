defmodule Aecore.Oracle.Tx.OracleQueryTx do
  @moduledoc """
  Contains the transaction structure for oracle queries
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.{Oracle, OracleQuery, OracleStateTree}
  alias Aeutil.Bits
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

  @version 1

  @type id :: binary()

  @type payload :: %{
          oracle_address: Identifier.t(),
          query_data: String.t(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @type t :: %OracleQueryTx{
          oracle_address: Identifier.t(),
          query_data: String.t(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @type tx_type_state() :: Chainstate.oracles()

  @nonce_size 256

  defstruct [
    :oracle_address,
    :query_data,
    :query_fee,
    :query_ttl,
    :response_ttl
  ]

  use ExConstructor

  @spec get_chain_state_name() :: :oracles
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
    identified_orc_address = Identifier.create_identity(oracle_address, :oracle)

    %OracleQueryTx{
      oracle_address: identified_orc_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }
  end

  @spec validate(OracleQueryTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %OracleQueryTx{
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          oracle_address: oracle_address
        },
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    cond do
      !Oracle.ttl_is_valid?(query_ttl) ->
        {:error, "#{__MODULE__}: Invalid query ttl"}

      !Oracle.ttl_is_valid?(response_ttl) ->
        {:error, "#{__MODULE__}: Invalid response ttl"}

      !match?(%{type: :relative}, response_ttl) ->
        {:error, "#{__MODULE__}: Invalid ttl type"}

      !validate_identifier(oracle_address) ->
        {:error, "#{__MODULE__}: Invalid oracle identifier: #{inspect(oracle_address)}"}

      !Keys.key_size_valid?(oracle_address.value) ->
        {:error, "#{__MODULE__}: oracle_adddress size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

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
        %OracleQueryTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    nonce = DataTx.nonce(data_tx)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.query_fee * -1)
      end)

    identified_sender = Identifier.create_identity(sender, :account)

    query = %OracleQuery{
      sender_address: identified_sender,
      sender_nonce: nonce,
      oracle_address: tx.oracle_address,
      query: tx.query_data,
      has_response: false,
      response: :undefined,
      expires: Oracle.calculate_absolute_ttl(tx.query_ttl, block_height),
      response_ttl: tx.response_ttl.ttl,
      fee: tx.query_fee
    }

    new_oracle_tree = OracleStateTree.insert_query(oracles, query)

    {:ok, {updated_accounts_state, new_oracle_tree}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        oracles,
        block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee - tx.query_fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx.ttl)}"}

      !OracleStateTree.exists_oracle?(oracles, tx.oracle_address.value) ->
        {:error, "#{__MODULE__}: No oracle registered with the address:
         #{inspect(tx.oracle_address)}"}

      !is_binary(tx.query_data) ->
        {:error, "#{__MODULE__}: Invalid query data: #{inspect(tx.query_data)}"}

      tx.query_fee < OracleStateTree.get_oracle(oracles, tx.oracle_address.value).query_fee ->
        {:error, "#{__MODULE__}: The query fee: #{inspect(tx.query_fee)} is
         lower than the one required by the oracle"}

      !is_minimum_fee_met?(tx, fee, block_height) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} is too low"}

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
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec get_oracle_query_fee(binary()) :: non_neg_integer()
  def get_oracle_query_fee(oracle_address) do
    Chain.chain_state().oracles
    |> OracleStateTree.get_oracle(oracle_address)
    |> Map.get(:query_fee)
  end

  @spec is_minimum_fee_met?(OracleQueryTx.t(), non_neg_integer(), non_neg_integer() | nil) ::
          boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    tx_query_fee_is_met =
      tx.query_fee >=
        Chain.chain_state().oracles
        |> OracleStateTree.get_oracle(tx.oracle_address.value)
        |> Map.get(:query_fee)

    tx_fee_is_met =
      case tx.query_ttl do
        %{ttl: ttl, type: :relative} ->
          fee >= calculate_minimum_fee(ttl)

        %{ttl: ttl, type: :absolute} ->
          if block_height != nil do
            fee >=
              ttl
              |> Oracle.calculate_relative_ttl(block_height)
              |> calculate_minimum_fee()
          else
            true
          end
      end

    tx_fee_is_met && tx_query_fee_is_met
  end

  @spec id(Keys.pubkey(), non_neg_integer(), Identifier.t()) :: binary()
  def id(sender, nonce, oracle_address) do
    bin = sender <> <<nonce::@nonce_size>> <> oracle_address
    Hash.hash(bin)
  end

  def base58c_encode(bin) do
    Bits.encode58c("qy", bin)
  end

  def base58c_decode(<<"qy$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec validate_identifier(Identifier.t()) :: boolean()
  defp validate_identifier(%Identifier{} = id) do
    Identifier.create_identity(id.value, :oracle) == id
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_query_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  def encode_to_list(%OracleQueryTx{} = tx, %DataTx{} = datatx) do
    ttl_type_q = Serialization.encode_ttl_type(tx.query_ttl)
    ttl_type_r = Serialization.encode_ttl_type(tx.response_ttl)
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      Identifier.encode_to_binary(tx.oracle_address),
      tx.query_data,
      :binary.encode_unsigned(tx.query_fee),
      ttl_type_q,
      tx.query_ttl.ttl,
      ttl_type_r,
      :binary.encode_unsigned(tx.response_ttl.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

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
