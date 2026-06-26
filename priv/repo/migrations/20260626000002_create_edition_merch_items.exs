defmodule SeshLab.Repo.Migrations.CreateEditionMerchItems do
  use Ecto.Migration

  def change do
    create table(:edition_merch_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :edition_id, references(:editions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :merch_item_id, references(:merch_items, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(updated_at: false)
    end

    create unique_index(:edition_merch_items, [:edition_id, :merch_item_id])
    create index(:edition_merch_items, [:edition_id])
  end
end
