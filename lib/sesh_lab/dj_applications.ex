defmodule SeshLab.DjApplications do
  @moduledoc """
  Inscrições do "QUER TOCAR?" — DJs pedindo espaço pra tocar na SESH.
  Espelha o Google Form. Anti-spam (honeypot, tempo mínimo, rate limit) fica
  na camada web; aqui só persistência + push pro admin.
  """

  import Ecto.Query

  alias SeshLab.{Notifications, Repo}
  alias SeshLab.DjApplications.DjApplication

  @spec create(map()) :: {:ok, DjApplication.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    case %DjApplication{} |> DjApplication.changeset(attrs) |> Repo.insert() do
      {:ok, application} = ok ->
        Notifications.notify_admin_dj_application(application)
        ok

      err ->
        err
    end
  end

  def change(%DjApplication{} = application \\ %DjApplication{}, attrs \\ %{}),
    do: DjApplication.changeset(application, attrs)

  @spec list() :: [DjApplication.t()]
  def list do
    DjApplication
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end
end
