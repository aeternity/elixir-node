defmodule Aecore.Structures.OracleQueryTxData do
  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle

  require Logger

  @type t :: %OracleQueryTxData{
          sender: binary(),
          oracle_hash: binary(),
          query_data: map(),
          query_fee: non_neg_integer(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:sender, :oracle_hash, :query_data, :query_fee, :fee, :nonce]
  use ExConstructor

  @spec create(binary(), map(), integer(), integer()) :: OracleQueryTxData.t()
  def create(oracle_hash, query_data, query_fee, fee) do
    registered_oracles = Chain.registered_oracles()

    cond do
      !Map.has_key?(registered_oracles, oracle_hash) ->
        Logger.error("No oracle registered with that hash")
        :error

      !Oracle.data_valid?(
        registered_oracles[oracle_hash].data.query_format,
        query_data
      ) ->
        :error

      true ->
        {:ok, pubkey} = Keys.pubkey()

        %OracleQueryTxData{
          sender: pubkey,
          oracle_hash: oracle_hash,
          query_data: query_data,
          query_fee: query_fee,
          fee: fee,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end
end
