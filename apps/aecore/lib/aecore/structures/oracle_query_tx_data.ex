defmodule Aecore.Structures.OracleQueryTxData do
  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aeutil.Bits

  require Logger

  @type t :: %OracleQueryTxData{
          sender: binary(),
          oracle_address: binary(),
          query_data: map(),
          query_fee: non_neg_integer(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:sender, :oracle_address, :query_data, :query_fee, :fee, :nonce]
  use ExConstructor

  @spec create(binary(), map(), integer(), integer()) :: OracleQueryTxData.t()
  def create(oracle_address, query_data, query_fee, fee) do
    registered_oracles = Chain.registered_oracles()

    cond do
      !Map.has_key?(registered_oracles, oracle_address) ->
        Logger.error("No oracle registered with that address")
        :error

      !Oracle.data_valid?(
        registered_oracles[oracle_address].data.query_format,
        query_data
      ) ->
        :error

      true ->
        {:ok, pubkey} = Keys.pubkey()

        %OracleQueryTxData{
          sender: pubkey,
          oracle_address: oracle_address,
          query_data: query_data,
          query_fee: query_fee,
          fee: fee,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("qy", bin)
  end
end
