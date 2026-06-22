defmodule SeshLab.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :key, :string, null: false, primary_key: true
      add :value, :string, null: false

      timestamps()
    end
  end
end
