defmodule SeshLab.Repo.Migrations.MakeOrderItemsPolymorphic do
  use Ecto.Migration

  def up do
    alter table(:order_items) do
      add :merch_item_id, references(:merch_items, type: :binary_id, on_delete: :restrict)
      add :merch_item_name_snapshot, :string
    end

    execute """
    CREATE TABLE order_items_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id BLOB NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      ticket_type_id BLOB REFERENCES ticket_types(id) ON DELETE RESTRICT,
      ticket_type_name_snapshot TEXT,
      merch_item_id BLOB REFERENCES merch_items(id) ON DELETE RESTRICT,
      merch_item_name_snapshot TEXT,
      quantity INTEGER NOT NULL,
      unit_price_cents INTEGER NOT NULL,
      inserted_at TEXT NOT NULL,
      CHECK (
        (ticket_type_id IS NOT NULL AND merch_item_id IS NULL)
        OR (ticket_type_id IS NULL AND merch_item_id IS NOT NULL)
      )
    )
    """

    execute """
    INSERT INTO order_items_new
      (id, order_id, ticket_type_id, ticket_type_name_snapshot, quantity, unit_price_cents, inserted_at)
    SELECT id, order_id, ticket_type_id, ticket_type_name_snapshot, quantity, unit_price_cents, inserted_at
    FROM order_items
    """

    execute "DROP TABLE order_items"
    execute "ALTER TABLE order_items_new RENAME TO order_items"

    create index(:order_items, [:order_id])
    create index(:order_items, [:merch_item_id])
  end

  def down do
    raise "irreversible: polymorphic order_items"
  end
end
