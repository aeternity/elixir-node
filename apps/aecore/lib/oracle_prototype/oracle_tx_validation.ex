defmodule Aecore.OraclePrototype.OracleTxValidation do

  require Logger

  @spec data_valid?(map(), map()) :: true | false
  def data_valid?(format, data) do
    schema = ExJsonSchema.Schema.resolve(format)
    case ExJsonSchema.Validator.validate(schema, data) do
      :ok ->
        true
      {:error, message} ->
        Logger.error(message)
        false
    end
  end
end
