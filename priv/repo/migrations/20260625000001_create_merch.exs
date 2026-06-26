defmodule SeshLab.Repo.Migrations.CreateMerch do
  use Ecto.Migration

  def change do
    create table(:merch_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :stock, :integer, null: false
      add :available, :integer, null: false
      add :image_path, :string
      add :is_active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      timestamps()
    end

    create index(:merch_items, [:is_active, :position])

    create table(:merch_units, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false

      add :merch_item_id, references(:merch_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :merch_item_name_snapshot, :string, null: false
      add :sold_edition_id, references(:editions, type: :binary_id, on_delete: :nilify_all)
      add :code, :string, null: false
      add :redeemed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:merch_units, [:code])
    create index(:merch_units, [:order_id])
    create index(:merch_units, [:merch_item_id])
  end
end
