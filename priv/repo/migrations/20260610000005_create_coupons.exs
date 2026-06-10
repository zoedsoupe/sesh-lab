defmodule SeshLab.Repo.Migrations.CreateCoupons do
  use Ecto.Migration

  def change do
    create table(:coupon_rules) do
      add :name, :string, null: false
      add :min_order_cents, :integer, null: false
      add :discount_kind, :string, null: false
      add :discount_value, :integer, null: false
      add :expires_in_days, :integer, null: false, default: 7
      add :is_active, :boolean, null: false, default: true

      timestamps()
    end

    create table(:coupons) do
      add :code, :string, null: false
      add :scope, :string, null: false
      add :discount_kind, :string, null: false
      add :discount_value, :integer, null: false
      add :expires_at, :utc_datetime
      add :min_order_cents, :integer
      add :is_active, :boolean, null: false, default: true

      # bound-only
      add :rule_id, references(:coupon_rules, on_delete: :nilify_all)
      add :customer_instagram, :string
      add :client_endpoint, :string
      add :order_id, :binary_id
      add :used_at, :utc_datetime
      add :used_order_id, :binary_id
      add :notified_expiring_at, :utc_datetime

      # public-only
      add :max_uses, :integer
      add :uses_count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:coupons, [:code])
    create index(:coupons, [:scope])
  end
end
