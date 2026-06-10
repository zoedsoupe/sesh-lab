defmodule SeshLab.DjApplications.DjApplication do
  @moduledoc """
  Inscrição do "QUER TOCAR?" — espelha o Google Form da SESH:
  nome, zap (DDD), instagram, estilos musicais e um sobre.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "dj_applications" do
    field :name, :string
    field :whatsapp, :string
    field :instagram, :string
    field :musical_styles, :string
    field :about, :string

    timestamps(updated_at: false)
  end

  @castable ~w(name whatsapp instagram musical_styles about)a
  @required @castable

  def changeset(application, attrs) do
    application
    |> cast(attrs, @castable)
    |> update_change(:whatsapp, &normalize_whatsapp/1)
    |> update_change(:instagram, &normalize_handle/1)
    |> validate_required(@required)
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:whatsapp, ~r/^\d{10,13}$/, message: "informe DDD + número")
    |> validate_length(:instagram, min: 1, max: 30)
    |> validate_format(:instagram, ~r/^[a-z0-9._]+$/,
      message: "use apenas letras, números, ponto ou underline"
    )
    |> validate_length(:musical_styles, min: 3, max: 1000)
    |> validate_length(:about, min: 3, max: 1000)
  end

  defp normalize_whatsapp(nil), do: nil
  defp normalize_whatsapp(value), do: String.replace(value, ~r/\D/, "")

  defp normalize_handle(nil), do: nil

  defp normalize_handle(handle),
    do: handle |> String.trim() |> String.trim_leading("@") |> String.downcase()
end
