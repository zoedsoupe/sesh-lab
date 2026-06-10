defmodule SeshLab.Settings.StoreSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "store_settings" do
    field :is_high_demand, :boolean, default: false

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:id, :is_high_demand])
    |> validate_required([:id, :is_high_demand])
  end
end
