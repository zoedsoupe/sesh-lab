defmodule SeshLab.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ticket_type_id, references(:ticket_types, type: :binary_id, on_delete: :restrict),
        null: false

      # Denormalized so door stats are a single indexed count.
      add :edition_id, references(:editions, type: :binary_id, on_delete: :restrict),
        null: false

      add :code, :string, null: false
      add :used_at, :utc_datetime

      timestamps()
    end

    create unique_index(:tickets, [:code])
    create index(:tickets, [:edition_id])
    create index(:tickets, [:order_id])
  end
end
