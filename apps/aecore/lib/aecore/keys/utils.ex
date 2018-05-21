defmodule Aecore.Keys.Utils do
  @moduledoc """
  Holds functionality for storing the keypairs in the project
  """

  @spec has_dir?(:ok, String.t()) :: :ok
  def has_dir?(:ok, path), do: {:error, :empty}

  @spec has_dir?(tuple(), String.t()) :: :ok
  def has_dir?({:error, :eexist}, path) do
    case get_file_name(path) do
      [] -> {:error, :empty}
      [_] -> :ok
    end
  end

  @spec has_dir?(tuple(), String.t()) :: {:error, String.t()}
  def has_dir?({:error, reason}, _path) do
    {:error, reason}
  end

  @spec get_file_name(String.t()) :: List.t()
  def get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard()
  end

  def password, do: Application.get_env(:aecore, :aewallet)[:pass]

  def read_file({:ok, encrypted_keys}) do
    {:ok, encrypted_keys}
  end

  def read_file({:error, reason}) do
    case reason do
      :enoent ->
        {:error, "The file does not exist."}

      :eaccess ->
        {:error, "Missing permision for reading the file,
        or for searching one of the parent directories."}

      :eisdir ->
        {:error, "The named file is a directory."}

      :enotdir ->
        {:error, "A component of the file name is not a directory."}

      :enomem ->
        {:error, "There is not enough memory for the contents of the file."}
    end
  end
end
