# Seeds de desenvolvimento: 2 edições com accents e lotes distintos.
# Idempotente: pula edições cujo `number` já existe.
#
#   mix run priv/repo/seeds.exs

import Ecto.Query

alias SeshLab.Editions
alias SeshLab.Editions.Edition
alias SeshLab.Repo

upsert = fn attrs ->
  number = attrs.number

  if Repo.exists?(from(e in Edition, where: e.number == ^number)) do
    IO.puts("· edição ##{number} já existe — pulando")
    nil
  else
    {:ok, ed} = Editions.create_edition(attrs)
    IO.puts("✓ criada edição ##{number}: #{ed.name} (#{ed.accent_color})")
    ed
  end
end

# Edição 1 — rosa (accent padrão), será a publicada/atual.
ed1 =
  upsert.(%{
    number: 1,
    name: "SESH #1",
    starts_at: ~U[2026-06-28 00:00:00Z],
    venue: "OCA ROOTS",
    venue_address: "Campos dos Goytacazes — RJ",
    lineup: "ANTUNIO\nBRED\nE CONVIDADOS",
    status: :draft,
    accent_color: "#F07BC0",
    ticket_types: [
      %{
        name: "Lista Amiga",
        description: "marque 2 amigos no post do Instagram (@coletivo.sesh)",
        price_cents: 1000,
        capacity: 50,
        position: 0,
        is_active: true
      },
      %{name: "Lote 1", price_cents: 1500, capacity: 80, position: 1, is_active: true},
      %{name: "Porta", price_cents: 2000, capacity: 40, position: 2, is_active: true}
    ]
  })

# Edição 2 — ciano neon (accent diferente), fica em draft.
upsert.(%{
  number: 2,
  name: "SESH #2",
  starts_at: ~U[2026-07-26 00:00:00Z],
  venue: "A DEFINIR",
  lineup: "LINEUP EM BREVE",
  status: :draft,
  accent_color: "#16C8D8",
  ticket_types: [
    %{
      name: "Pré-venda",
      description: "primeiro lote, preço amigo — corre que acaba",
      price_cents: 1200,
      capacity: 100,
      position: 0,
      is_active: true
    },
    %{name: "Pista", price_cents: 2500, capacity: 120, position: 1, is_active: false}
  ]
})

# Publica a #1 (vira a edição atual da landing; arquiva qualquer outra publicada).
if ed1, do: {:ok, _} = Editions.publish(ed1)
IO.puts("seeds ok")
