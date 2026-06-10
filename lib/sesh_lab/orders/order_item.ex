defmodule SeshLab.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Orders.Order

  @type t :: %__MODULE__{}

  @foreign_key_type :binary_id
  schema "order_items" do
    belongs_to :order, Order, type: :binary_id
    field :product_id, :string
    field :product_name_snapshot, :string
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :lead_time_days_snapshot, :integer

    timestamps(updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(
      attrs,
      ~w(order_id product_id product_name_snapshot quantity unit_price_cents
         lead_time_days_snapshot)a
    )
    |> validate_required(~w(product_id product_name_snapshot quantity unit_price_cents)a)
    |> validate_number(:quantity, greater_than: 0)
  end
end
