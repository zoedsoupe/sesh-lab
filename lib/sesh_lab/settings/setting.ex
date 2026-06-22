defmodule SeshLab.Settings.Setting do
  @moduledoc "KV row. Values are strings; typed coercion lives in SeshLab.Settings."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :string
    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
  end
end
