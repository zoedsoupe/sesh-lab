defmodule SeshLab.Repo.Migrations.MakeOrdersEditionNullable do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Repo.checkout pins ONE connection for the whole fn and opens NO transaction,
    # so PRAGMA foreign_keys=OFF sticks across the DROP. Without this, DROP TABLE
    # orders cascade-deletes order_items/tickets/merch_units (FK ON DELETE).
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys=OFF")

      repo().query!("""
      CREATE TABLE orders_new (
        id TEXT PRIMARY KEY,
        edition_id TEXT REFERENCES editions(id) ON DELETE RESTRICT,
        status TEXT NOT NULL DEFAULT 'pending',
        customer_name TEXT NOT NULL,
        customer_instagram TEXT NOT NULL,
        total_cents INTEGER NOT NULL,
        coupon_code TEXT,
        discount_cents INTEGER NOT NULL DEFAULT 0,
        pix_key TEXT,
        client_endpoint TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO orders_new
        (id, edition_id, status, customer_name, customer_instagram, total_cents,
         coupon_code, discount_cents, pix_key, client_endpoint, inserted_at, updated_at)
      SELECT
         id, edition_id, status, customer_name, customer_instagram, total_cents,
         coupon_code, discount_cents, pix_key, client_endpoint, inserted_at, updated_at
      FROM orders
      """)

      repo().query!("DROP TABLE orders")
      repo().query!("ALTER TABLE orders_new RENAME TO orders")
      repo().query!("CREATE INDEX orders_status_index ON orders (status)")
      repo().query!("CREATE INDEX orders_edition_id_index ON orders (edition_id)")
      repo().query!("PRAGMA foreign_key_check")
      repo().query!("PRAGMA foreign_keys=ON")
    end)
  end

  def down, do: raise("irreversible: orders.edition_id nullable")
end
