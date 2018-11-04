defmodule Aeutil.Environment do
  @moduledoc """
  utility for providing environment specific variables
  """

  def core_priv_dir, do: Application.app_dir(:aecore, "priv")

  def core_priv_dir(dir), do: Path.join([core_priv_dir(), dir])

  def get_env_or_default(environment_variable, default) do
    case System.get_env(environment_variable) do
      nil -> default
      env -> env
    end
  end

  def get_env_or_core_priv_dir(environment_variable, dir),
    do: get_env_or_default(environment_variable, core_priv_dir(dir))
end
