defmodule SeshLab.Repo.Migrations.CreateDjApplications do
  use Ecto.Migration

  def change do
    create table(:dj_applications) do
      add :name, :string, null: false
      add :whatsapp, :string, null: false
      add :instagram, :string, null: false
      add :musical_styles, :text, null: false
      add :about, :text, null: false

      timestamps(updated_at: false)
    end
  end
end
