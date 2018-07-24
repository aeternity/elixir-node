defmodule Aecore.Naming.NameUtil do
  @moduledoc """
  Aecore naming utilities.
  """

  alias Aeutil.Hash
  alias Aecore.Governance.GovernanceConstants

  @spec normalized_namehash(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def normalized_namehash(name) do
    case normalize_and_validate_name(name) do
      {:ok, normalized_name} -> {:ok, namehash(normalized_name)}
      err -> err
    end
  end

  @spec normalize_and_validate_name(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_and_validate_name(name) do
    normalized_name = normalize_name(name)

    case validate_normalized_name(normalized_name) do
      :ok -> {:ok, normalized_name}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name), do: name |> :idna.utf8_to_ascii() |> to_string()

  @spec namehash(String.t()) :: binary()
  defp namehash(name) do
    if name == "" do
      <<0::256>>
    else
      {label, remainder} = partition_name(name)

      Hash.hash(namehash(remainder) <> Hash.hash(label))
    end
  end

  @spec partition_name(String.t()) :: {String.t(), String.t()}
  defp partition_name(name) do
    [label | remainder] = split_name(name)
    {label, Enum.join(remainder, GovernanceConstants.split_name_symbol())}
  end

  @spec validate_normalized_name(String.t()) :: :ok | {:error, String.t()}
  defp validate_normalized_name(name) do
    allowed_registrar =
      GovernanceConstants.name_registrars()
      |> Enum.any?(fn registrar -> String.ends_with?(name, registrar) end)

    if allowed_registrar do
      validate_name_length(name)
    else
      {:error, "#{__MODULE__}: name doesn't end with allowed registrar: #{inspect(name)}"}
    end
  end

  @spec get_max_name_length :: non_neg_integer()
  def get_max_name_length do
    Application.get_env(:aecore, :naming)[:max_name_length]
  end

  @spec validate_name_length(String.t()) :: :ok | {:error, String.t()}
  defp validate_name_length(name) do
    case String.length(name) > 0 && String.length(name) < get_max_name_length() do
      true ->
        labels = split_name(name)
        validate_label_length(labels)

      false ->
        {:error, "#{__MODULE__}: name has not the correct length: #{inspect(name)}"}
    end
  end

  @spec split_name(String.t()) :: [String.t()]
  defp split_name(name), do: String.split(name, GovernanceConstants.split_name_symbol())

  @spec get_max_label_length :: non_neg_integer()
  def get_max_label_length do
    Application.get_env(:aecore, :naming)[:max_label_length]
  end

  @spec validate_label_length([]) :: :ok
  defp validate_label_length([]) do
    :ok
  end

  @spec validate_label_length(list(String.t())) :: :ok | {:error, String.t()}
  defp validate_label_length([label | remainder]) do
    case String.length(label) > 0 && String.length(label) <= get_max_label_length() do
      true -> validate_label_length(remainder)
      false -> {:error, "#{__MODULE__}: label has not the correct length: #{inspect(label)}"}
    end
  end
end
