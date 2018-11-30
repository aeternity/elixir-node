defmodule Aecore.Chain.KeyBlock do
  @moduledoc """
  Module defining the KeyBlock structure
  """
  alias Aecore.Chain.{KeyBlock, KeyHeader, Target}
  alias Aecore.Pow.Pow

  @type t :: %KeyBlock{
          header: KeyHeader.t()
        }

  defstruct [:header]

  @spec validate(KeyBlock.t(), list(KeyBlock.t())) :: :ok | {:error, String.t()}
  def validate(
        %KeyBlock{
          header: %KeyHeader{target: target, time: time} = header
        },
        blocks_for_target_calculation
      ) do
    expected_target =
      Target.calculate_next_target(
        time,
        blocks_for_target_calculation
      )

    cond do
      target != expected_target ->
        {:error, "#{__MODULE__}: Invalid block target"}

      !Pow.solution_valid?(header) ->
        {:error, "#{__MODULE__}: Invalid PoW solution"}

      true ->
        :ok
    end
  end

  @spec encode_to_binary(KeyBlock.t()) :: binary()
  def encode_to_binary(%KeyBlock{header: header}) do
    KeyHeader.encode_to_binary(header)
  end

  @spec decode_from_binary(binary()) :: {:ok, KeyBlock.t()} | {:error, String.t()}
  def decode_from_binary(binary) when is_binary(binary) do
    case KeyHeader.decode_from_binary(binary) do
      {:ok, header} -> {:ok, %KeyBlock{header: header}}
      {:error, _reason} = error -> error
    end
  end
end
