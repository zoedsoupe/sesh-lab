defmodule SeshLab.Promos.Promo do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Promos.PromoItem

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "promos" do
    field :name, :string
    field :description, :string
    field :total_cents, :integer
    field :photo_path, :string
    field :is_active, :boolean, default: true

    has_many :items, PromoItem,
      foreign_key: :promo_id,
      on_delete: :delete_all,
      on_replace: :delete

    timestamps()
  end

  @castable ~w(id name description total_cents photo_path is_active)a
  @required ~w(id name total_cents)a

  def changeset(promo, attrs) do
    promo
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_number(:total_cents, greater_than: 0)
    |> validate_format(:id, ~r/^[a-z0-9-]+$/,
      message: "use apenas letras minúsculas, números ou hífen"
    )
    |> validate_length(:id, min: 2, max: 40)
    |> cast_assoc(:items, with: &PromoItem.changeset/2, required: true)
  end

  def admin_changeset(promo, attrs) do
    promo
    |> cast(attrs, @castable -- [:id])
    |> validate_required(@required -- [:id])
    |> validate_number(:total_cents, greater_than: 0)
    |> cast_assoc(:items, with: &PromoItem.changeset/2, required: true)
  end
end
