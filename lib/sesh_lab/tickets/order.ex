defmodule SeshLab.Tickets.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Tickets.{OrderItem, Ticket}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :status, Ecto.Enum,
      values: [:pending, :confirmed, :cancelled, :expired],
      default: :pending

    field :edition_id, :binary_id
    field :customer_name, :string
    field :customer_instagram, :string
    field :total_cents, :integer
    field :coupon_code, :string
    field :discount_cents, :integer, default: 0
    field :expires_at, :utc_datetime
    field :pix_key, :string
    # Push endpoint of the device that placed the order (for status notifications).
    field :client_endpoint, :string

    has_many :items, OrderItem, foreign_key: :order_id, on_delete: :delete_all
    has_many :tickets, Ticket, foreign_key: :order_id, on_delete: :delete_all

    timestamps()
  end

  @castable ~w(edition_id customer_name customer_instagram total_cents coupon_code
               discount_cents expires_at status pix_key client_endpoint)a
  @required ~w(edition_id customer_name customer_instagram total_cents)a

  def changeset(order, attrs) do
    order
    |> cast(attrs, @castable)
    |> update_change(:customer_instagram, &normalize_handle/1)
    |> validate_required(@required)
    |> validate_length(:customer_name, min: 2, max: 80)
    |> validate_length(:customer_instagram, min: 1, max: 30)
    |> validate_format(:customer_instagram, ~r/^[a-z0-9._]+$/,
      message: "use apenas letras, números, ponto ou underline"
    )
  end

  @doc "Normaliza handle do Instagram: trim, remove @ inicial, lowercase."
  def normalize_handle(nil), do: nil

  def normalize_handle(handle) do
    handle |> String.trim() |> String.trim_leading("@") |> String.downcase()
  end
end
