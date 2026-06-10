defmodule SeshLab.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :edition_id, references(:editions, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "pending"
      add :customer_name, :string, null: false
      add :customer_instagram, :string, null: false
      add :total_cents, :integer, null: false
      add :coupon_code, :string
      add :discount_cents, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :pix_key, :string
      add :client_endpoint, :string

      timestamps()
    end

    create index(:orders, [:status, :expires_at])
    create index(:orders, [:edition_id])

    create table(:order_items) do
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ticket_type_id, references(:ticket_types, type: :binary_id, on_delete: :restrict),
        null: false

      add :ticket_type_name_snapshot, :string, null: false
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false

      timestamps(updated_at: false)
    end

    create index(:order_items, [:order_id])
  end
end
