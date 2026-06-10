defmodule SeshLab.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions) do
      add :endpoint, :string, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :user_agent, :string
      add :audience, :string, null: false, default: "admin"
      add :topics, {:array, :string}, null: false, default: []

      timestamps()
    end

    create unique_index(:push_subscriptions, [:endpoint])
  end
end
