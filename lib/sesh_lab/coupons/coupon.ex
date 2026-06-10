defmodule SeshLab.Coupons.Coupon do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "coupons" do
    field :code, :string
    field :scope, Ecto.Enum, values: [:bound, :public]
    field :discount_kind, Ecto.Enum, values: [:percent, :fixed]
    field :discount_value, :integer
    field :expires_at, :utc_datetime
    field :min_order_cents, :integer
    field :is_active, :boolean, default: true

    # bound-only
    field :rule_id, :id
    field :customer_instagram, :string
    field :client_endpoint, :string
    field :order_id, :binary_id
    field :used_at, :utc_datetime
    field :used_order_id, :binary_id
    field :notified_expiring_at, :utc_datetime

    # public-only
    field :max_uses, :integer
    field :uses_count, :integer, default: 0

    timestamps()
  end

  @doc "Changeset for an admin-created public coupon."
  def public_changeset(coupon, attrs) do
    coupon
    |> cast(attrs, ~w(code discount_kind discount_value expires_at min_order_cents
                      max_uses is_active)a)
    |> put_change(:scope, :public)
    |> update_change(:code, &normalize_code/1)
    |> validate_required(~w(code discount_kind discount_value)a)
    |> validate_length(:code, min: 3, max: 32)
    |> validate_format(:code, ~r/^[A-Z0-9-]+$/, message: "use letras, números ou hífen")
    |> validate_number(:max_uses, greater_than: 0)
    |> validate_number(:min_order_cents, greater_than: 0)
    |> validate_discount()
    |> unique_constraint(:code)
  end

  @doc "Changeset for a system-issued bound coupon (no user input)."
  def bound_changeset(attrs) do
    %__MODULE__{scope: :bound}
    |> cast(attrs, ~w(code discount_kind discount_value expires_at rule_id
                      customer_instagram client_endpoint order_id)a)
    |> validate_required(~w(code discount_kind discount_value expires_at customer_instagram)a)
    |> validate_discount()
    |> unique_constraint(:code)
  end

  @doc "Validates `discount_value` against `discount_kind` (percent 1..100, fixed > 0)."
  def validate_discount(changeset) do
    case get_field(changeset, :discount_kind) do
      :percent ->
        validate_number(changeset, :discount_value,
          greater_than: 0,
          less_than_or_equal_to: 100
        )

      :fixed ->
        validate_number(changeset, :discount_value, greater_than: 0)

      _ ->
        changeset
    end
  end

  @doc "Discount in cents this coupon yields on `subtotal_cents`."
  @spec discount_cents(t() | map(), non_neg_integer()) :: non_neg_integer()
  def discount_cents(%{discount_kind: :percent, discount_value: v}, subtotal),
    do: round(subtotal * v / 100)

  def discount_cents(%{discount_kind: :fixed, discount_value: v}, subtotal),
    do: min(v, subtotal)

  defp normalize_code(nil), do: nil
  defp normalize_code(code), do: code |> String.trim() |> String.upcase()
end
