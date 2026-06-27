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

# ── Merch (catálogo global da loja) ───────────────────────────────────────────
# Idempotente: pula itens cujo `name` já existe.
alias SeshLab.Merch
alias SeshLab.Merch.Item

merch_upsert = fn attrs ->
  if Repo.exists?(from(m in Item, where: m.name == ^attrs.name)) do
    IO.puts("· merch “#{attrs.name}” já existe — pulando")
  else
    {:ok, item} = Merch.create_item(attrs)
    IO.puts("✓ criado merch: #{item.name} (#{item.available}/#{item.stock})")
  end
end

[
  %{
    name: "Bolsinha",
    description: "lona, serigrafia da casa",
    price_cents: 3000,
    stock: 25,
    position: 0
  },
  %{
    name: "Adesivo",
    description: "vinil holográfico, 8cm",
    price_cents: 500,
    stock: 200,
    position: 1
  },
  %{
    name: "Poster A3",
    description: "fosco 250g, edição numerada",
    price_cents: 2500,
    stock: 40,
    position: 2
  },
  %{
    name: "Camiseta",
    description: "preta, estampa SESH nas costas",
    price_cents: 6000,
    stock: 30,
    position: 3,
    is_active: false
  },
  # Balcão (POS da festa). Água/cerveja rastreiam estoque; cigarro/pirulito não.
  %{name: "Água", price_cents: 500, kind: :counter, track_stock: true, stock: 60, position: 0},
  %{
    name: "Cerveja",
    price_cents: 1000,
    kind: :counter,
    track_stock: true,
    stock: 120,
    position: 1
  },
  %{name: "Cigarro", price_cents: 200, kind: :counter, track_stock: false, position: 2},
  %{name: "Pirulito", price_cents: 300, kind: :counter, track_stock: false, position: 3}
]
|> Enum.each(merch_upsert)

IO.puts("seeds ok")
