defmodule SeshLab.Fixtures do
  @moduledoc "Builders compartilhados pros testes de domínio."

  alias SeshLab.Repo
  alias SeshLab.Editions.{Edition, TicketType}
  alias SeshLab.Tickets.Order

  def edition_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      number: n,
      name: "SESH ##{n}",
      starts_at: DateTime.add(DateTime.utc_now(), 7 * 86_400) |> DateTime.truncate(:second),
      venue: "OCA ROOTS",
      status: :published,
      accent_color: "#F07BC0"
    }

    %Edition{}
    |> Edition.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def ticket_type_fixture(edition, attrs \\ %{}) do
    capacity = Map.get(attrs, :capacity, 10)

    defaults = %{
      name: "Lote 1",
      price_cents: 1000,
      capacity: capacity,
      available: capacity,
      is_active: true
    }

    %TicketType{edition_id: edition.id}
    |> struct(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @doc "Edição + um lote, prontos pra comprar."
  def edition_with_lot(edition_attrs \\ %{}, lot_attrs \\ %{}) do
    edition = edition_fixture(edition_attrs)
    lot = ticket_type_fixture(edition, lot_attrs)
    {edition, lot}
  end

  def order_attrs(edition, lot, overrides \\ %{}) do
    Map.merge(
      %{
        edition_id: edition.id,
        customer_name: "Fulano",
        customer_instagram: "fulano",
        items: [%{ticket_type_id: lot.id, quantity: 1}]
      },
      overrides
    )
  end

  def insert_order(edition, attrs \\ %{}) do
    defaults = %{
      edition_id: edition.id,
      customer_name: "Fulano",
      customer_instagram: "fulano",
      total_cents: 10_000,
      status: :pending
    }

    Repo.insert!(struct(%Order{}, Map.merge(defaults, attrs)))
  end
end
