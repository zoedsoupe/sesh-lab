defmodule SeshLab.Settings do
  @moduledoc """
  KV de configuração runtime, flipável pelo admin e persistido (sobrevive a
  restart). Valores são strings; os acessores tipados coercem.

  # ponytail: sem cache, sem JSON, sem valores tipados no schema. Cada read é
  # uma query — correto pro volume deste site. Gatilho pra revisitar: um flag
  # que precise de dado estruturado (vira coluna JSON ou tabela própria).
  """
  alias SeshLab.Repo
  alias SeshLab.Settings.Setting

  @dj_applications_open "dj_applications_open"

  @spec get_bool(String.t(), boolean()) :: boolean()
  def get_bool(key, default) when is_boolean(default) do
    case Repo.get(Setting, key) do
      %Setting{value: "true"} -> true
      %Setting{value: "false"} -> false
      _ -> default
    end
  end

  @spec put_bool(String.t(), boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def put_bool(key, value) when is_boolean(value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: to_string(value)})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end

  @doc "Default: open. A flag só existe quando o admin fecha pela primeira vez."
  @spec dj_applications_open?() :: boolean()
  def dj_applications_open?, do: get_bool(@dj_applications_open, true)

  @spec set_dj_applications_open(boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_dj_applications_open(open?) when is_boolean(open?),
    do: put_bool(@dj_applications_open, open?)
end
