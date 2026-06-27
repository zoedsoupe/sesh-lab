defmodule SeshLab.Bar.SaleItem do
  @moduledoc """
  Linha de uma venda de balcão. `name_snapshot`/`unit_price_cents` congelam o
  item no momento da venda (preço pode mudar depois).
  """
  use Ecto.Schema

  alias SeshLab.Bar.Sale
  alias SeshLab.Merch.Item

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bar_sale_items" do
    field :name_snapshot, :string
    field :quantity, :integer
    field :unit_price_cents, :integer

    belongs_to :sale, Sale, foreign_key: :bar_sale_id
    belongs_to :merch_item, Item

    timestamps(updated_at: false)
  end
end
