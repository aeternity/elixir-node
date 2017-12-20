defmodule Aecore.Structures.OracleRegistrationTxData do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys

  defstruct [:operator,
             :query_format,
             :response_format,
             :description,
             :fee]

  @spec create(map(), map(), binary(), integer()) :: %OracleRegistrationTxData{}
  def create(query_format, response_format, description, fee) do
    {:ok, pubkey} = Keys.pubkey()
    %OracleRegistrationTxData{operator: pubkey,
                              query_format: query_format,
                              response_format: response_format,
                              description: description, fee: fee}
  end
end
