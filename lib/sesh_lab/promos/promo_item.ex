defmodule SeshLab.Promos.PromoItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Catalog.Product
  alias SeshLab.Promos.Promo

  @type t :: %__MODULE__{}

  schema "promo_items" do
    belongs_to :promo, Promo, type: :string
    belongs_to :product, Product, type: :string
    field :quantity, :integer

    timestamps(updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, ~w(promo_id product_id quantity)a)
    |> validate_required(~w(product_id quantity)a)
    |> validate_number(:quantity, greater_than: 0)
  end
end
