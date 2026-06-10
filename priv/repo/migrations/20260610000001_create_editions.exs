defmodule SeshLab.Repo.Migrations.CreateEditions do
  use Ecto.Migration

  def change do
    create table(:editions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :name, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :venue, :string, null: false
      add :venue_address, :string
      add :lineup, :text
      add :status, :string, null: false, default: "draft"
      add :accent_color, :string, null: false, default: "#F07BC0"
      add :logo_path, :string

      timestamps()
    end

    create unique_index(:editions, [:number])
    create index(:editions, [:status])

    create table(:ticket_types, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :edition_id, references(:editions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :price_cents, :integer, null: false
      add :capacity, :integer, null: false
      add :available, :integer, null: false
      add :is_active, :boolean, null: false, default: true
      add :opens_at, :utc_datetime
      add :closes_at, :utc_datetime
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:ticket_types, [:edition_id])
  end
end
