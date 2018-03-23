defmodule Aecore.Naming.Util do
  alias Aeutil.Hash

  @split_name_symbol "."

  @name_registrars [@split_name_symbol <> "aet", @split_name_symbol <> "test"]

  @spec namehash(String.t()) :: binary()
  def namehash(name) do
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
    {label, Enum.join(remainder, @split_name_symbol)}
  end

  @spec normalized_hash!(String.t()) :: binary()
  def normalized_hash!(name) do
    case normalize_and_validate_name(name) do
      {:ok, normalized_name} -> Hash.hash(normalized_name)
      {:error, error} -> throw(error)
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
  def normalize_name(name),
    do:
      name
      |> :idna.utf8_to_ascii()
      |> to_string()

  @spec validate_normalized_name(String.t()) :: :ok | {:error, String.t()}
  defp validate_normalized_name(name) do
    allowed_registrar =
      Enum.any?(@name_registrars, fn registrar -> String.ends_with?(name, registrar) end)

    if allowed_registrar do
      validate_name_length(name)
    else
      {:error, "name doesn't end with allowed registrar"}
    end
  end

  @spec validate_name_length(String.t()) :: :ok | {:error, String.t()}
  defp validate_name_length(name) do
    case String.length(name) > 0 && String.length(name) < 253 do
      true ->
        labels = split_name(name)
        validate_label_length(labels)

      false ->
        {:error, "name has not the correct length"}
    end
  end

  @spec split_name(String.t()) :: [String.t()]
  defp split_name(name), do: String.split(name, @split_name_symbol)

  @spec validate_label_length([]) :: :ok
  defp validate_label_length([]) do
    :ok
  end

  @spec validate_label_length(list(String.t())) :: :ok | {:error, String.t()}
  defp validate_label_length([label | remainder]) do
    case String.length(label) > 0 && String.length(label) <= 63 do
      true -> validate_label_length(remainder)
      false -> {:error, "label has not the correct length"}
    end
  end
end
