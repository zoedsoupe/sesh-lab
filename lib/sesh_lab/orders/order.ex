defmodule SeshLab.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Orders.OrderItem

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :status, Ecto.Enum,
      values: [:pending, :confirmed, :cancelled, :expired],
      default: :pending

    field :customer_name, :string
    field :customer_instagram, :string
    field :delivery_type, Ecto.Enum, values: [:retirada, :entrega, :envio, :outro]
    field :address, :string
    field :payment_method, Ecto.Enum, values: [:pix, :dinheiro, :credito]
    field :total_cents, :integer
    field :pix_key, :string
    field :notes, :string
    field :expires_at, :utc_datetime
    field :promo_id, :string
    # Push endpoint of the device that placed the order (for status notifications).
    field :client_endpoint, :string
    field :coupon_code, :string
    field :discount_cents, :integer, default: 0

    has_many :items, OrderItem, foreign_key: :order_id, on_delete: :delete_all

    timestamps()
  end

  @castable ~w(customer_name customer_instagram delivery_type address payment_method
               total_cents pix_key notes expires_at status promo_id client_endpoint
               coupon_code discount_cents)a
  @required ~w(customer_name customer_instagram delivery_type payment_method total_cents)a

  def changeset(order, attrs) do
    order
    |> cast(attrs, @castable)
    |> update_change(:customer_instagram, &normalize_handle/1)
    |> validate_required(@required)
    |> validate_address()
    |> validate_length(:customer_name, min: 2, max: 80)
    |> validate_length(:customer_instagram, min: 1, max: 30)
    |> validate_format(:customer_instagram, ~r/^[a-z0-9._]+$/,
      message: "use apenas letras, números, ponto ou underline"
    )
  end

  defp validate_address(changeset) do
    case get_field(changeset, :delivery_type) do
      :envio -> validate_required(changeset, [:address])
      _ -> changeset
    end
  end

  defp normalize_handle(nil), do: nil

  defp normalize_handle(handle) do
    handle
    |> String.trim()
    |> String.trim_leading("@")
    |> String.downcase()
  end
end
