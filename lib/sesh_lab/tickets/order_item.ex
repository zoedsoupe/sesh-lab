defmodule SeshLab.Tickets.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Tickets.Order

  @type t :: %__MODULE__{}

  @foreign_key_type :binary_id
  schema "order_items" do
    belongs_to :order, Order, type: :binary_id
    field :ticket_type_id, :binary_id
    field :ticket_type_name_snapshot, :string
    field :quantity, :integer
    field :unit_price_cents, :integer

    timestamps(updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(
      attrs,
      ~w(order_id ticket_type_id ticket_type_name_snapshot quantity unit_price_cents)a
    )
    |> validate_required(~w(ticket_type_id ticket_type_name_snapshot quantity unit_price_cents)a)
    |> validate_number(:quantity, greater_than: 0)
  end
end
