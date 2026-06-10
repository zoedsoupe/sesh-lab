defmodule SeshLab.Settings do
  @moduledoc """
  Configuração global da loja. Linha singleton em `store_settings`.

  `is_high_demand` controla o aviso na tela de confirmação de pedido
  ("a sesh está com alta demanda, tempo de confirmação pode variar").
  Diana liga/desliga pelo painel admin.
  """

  alias SeshLab.Repo
  alias SeshLab.Settings.StoreSettings

  @singleton_id "default"
  @topic "admin:store_settings"

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec get() :: StoreSettings.t()
  def get do
    case Repo.get(StoreSettings, @singleton_id) do
      nil ->
        {:ok, settings} =
          %StoreSettings{}
          |> StoreSettings.changeset(%{id: @singleton_id, is_high_demand: false})
          |> Repo.insert()

        settings

      settings ->
        settings
    end
  end

  @spec high_demand?() :: boolean()
  def high_demand?, do: get().is_high_demand

  @spec set_high_demand(boolean()) :: {:ok, StoreSettings.t()} | {:error, Ecto.Changeset.t()}
  def set_high_demand(value) when is_boolean(value) do
    result =
      get()
      |> StoreSettings.changeset(%{is_high_demand: value})
      |> Repo.update()

    case result do
      {:ok, settings} ->
        broadcast({:high_demand_changed, settings.is_high_demand})
        {:ok, settings}

      err ->
        err
    end
  end

  @spec toggle_high_demand() :: {:ok, StoreSettings.t()} | {:error, Ecto.Changeset.t()}
  def toggle_high_demand do
    set_high_demand(not get().is_high_demand)
  end

  defp broadcast(msg) do
    Phoenix.PubSub.broadcast(SeshLab.PubSub, @topic, msg)
  end
end
