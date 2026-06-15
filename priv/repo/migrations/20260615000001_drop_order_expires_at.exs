defmodule SeshLab.Repo.Migrations.DropOrderExpiresAt do
  use Ecto.Migration

  # Pending orders no longer hold capacity — capacity is claimed at confirm time,
  # so there is no TTL and no expiry sweep. Drop the now-dead column and its
  # composite index; keep a plain status index for `Tickets.list_pending/0`.
  def up do
    drop_if_exists index(:orders, [:status, :expires_at])

    alter table(:orders) do
      remove :expires_at
    end

    create index(:orders, [:status])
  end

  def down do
    drop_if_exists index(:orders, [:status])

    alter table(:orders) do
      add :expires_at, :utc_datetime
    end

    create index(:orders, [:status, :expires_at])
  end
end
