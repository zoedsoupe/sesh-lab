defmodule SeshLab.Repo.Migrations.CreateBarSales do
  use Ecto.Migration

  def change do
    # Counter vs online split + optional per-item stock. Plain ADD COLUMN (no
    # SQLite table rebuild): existing rows stay online + tracked.
    alter table(:merch_items) do
      add :kind, :string, null: false, default: "online"
      add :track_stock, :boolean, null: false, default: true
    end

    # One row per counter checkout (cash or instant PIX). No customer, no code,
    # no Unit — consumed on the spot. Immutable: inserted_at only.
    create table(:bar_sales, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edition_id, references(:editions, type: :binary_id, on_delete: :restrict)
      add :payment_method, :string, null: false
      add :total_cents, :integer, null: false
      timestamps(updated_at: false)
    end

    create index(:bar_sales, [:edition_id])
    create index(:bar_sales, [:payment_method])

    create table(:bar_sale_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bar_sale_id, references(:bar_sales, type: :binary_id, on_delete: :delete_all),
        null: false

      add :merch_item_id, references(:merch_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :name_snapshot, :string, null: false
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false
      timestamps(updated_at: false)
    end

    create index(:bar_sale_items, [:bar_sale_id])
    create index(:bar_sale_items, [:merch_item_id])
  end
end
