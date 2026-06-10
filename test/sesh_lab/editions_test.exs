defmodule SeshLab.EditionsTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Editions, Repo}
  alias SeshLab.Editions.{Edition, TicketType}

  describe "current_edition/0" do
    test "returns only the published edition" do
      _draft = edition_fixture(%{status: :draft})
      published = edition_fixture(%{status: :published})
      _past = edition_fixture(%{status: :past})

      assert %Edition{id: id} = Editions.current_edition()
      assert id == published.id
    end

    test "nil when nothing is published" do
      edition_fixture(%{status: :draft})
      assert Editions.current_edition() == nil
    end
  end

  describe "publish/1" do
    test "publishing demotes the previously published edition to past" do
      first = edition_fixture(%{status: :published})
      second = edition_fixture(%{status: :draft})

      assert {:ok, _} = Editions.publish(second)
      assert Repo.get!(Edition, first.id).status == :past
      assert Repo.get!(Edition, second.id).status == :published
      assert Editions.current_edition().id == second.id
    end
  end

  describe "ticket type capacity sync" do
    test "new lot sets available = capacity via changeset" do
      edition = edition_fixture()

      {:ok, edition} =
        Editions.update_edition(edition, %{
          "ticket_types" => %{
            "0" => %{"name" => "Lote 1", "price_cents" => "1000", "capacity" => "20"}
          }
        })

      [lot] = edition.ticket_types
      assert lot.available == 20
    end

    test "raising capacity bumps available by the delta, preserving holds" do
      edition = edition_fixture()
      lot = ticket_type_fixture(edition, %{capacity: 10, available: 4})

      {:ok, lot} =
        lot
        |> TicketType.changeset(%{"capacity" => "15"})
        |> Repo.update()

      # delta +5 applied to the 4 still available.
      assert lot.capacity == 15
      assert lot.available == 9
    end
  end
end
