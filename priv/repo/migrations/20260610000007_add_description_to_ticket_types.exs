defmodule SeshLab.Repo.Migrations.AddDescriptionToTicketTypes do
  use Ecto.Migration

  def change do
    alter table(:ticket_types) do
      # Texto livre por lote: regras de desbloqueio/validação
      # (ex: "Lista Amiga" → "marque 2 amigos no post do Instagram").
      add :description, :text
    end
  end
end
