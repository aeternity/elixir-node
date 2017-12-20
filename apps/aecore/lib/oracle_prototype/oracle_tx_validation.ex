defmodule Aecore.OraclePrototype.OracleTxValidation do

  require Logger

  @spec validate_data(map(), map()) :: true | false
  def validate_data(format, data) do
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
