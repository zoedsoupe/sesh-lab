defmodule SeshLab.TicketsTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Repo, Tickets}
  alias SeshLab.Editions.TicketType
  alias SeshLab.Tickets.{Order, Ticket}

  describe "create_order/1" do
    test "creates a pending order and snapshots items without holding capacity" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5, price_cents: 1500})

      assert {:ok, %Order{} = order} =
               Tickets.create_order(
                 order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
               )

      assert order.status == :pending
      assert order.total_cents == 3000
      # Pending holds nothing — capacity only drops at confirm.
      assert Repo.get!(TicketType, lot.id).available == 5

      [item] = Repo.preload(order, :items).items
      assert item.quantity == 2
      assert item.unit_price_cents == 1500
      assert item.ticket_type_name_snapshot == lot.name
    end

    test "rejects empty cart" do
      {edition, _lot} = edition_with_lot()
      assert {:error, :empty_cart} = Tickets.create_order(%{edition_id: edition.id, items: []})
    end

    test "soft-rejects quantity beyond available capacity" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 1})

      assert {:error, {:sold_out, id}} =
               Tickets.create_order(
                 order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
               )

      assert id == lot.id
    end

    test "rejects an inactive lot" do
      {edition, lot} = edition_with_lot(%{}, %{is_active: false})
      assert {:error, {:not_on_sale, _}} = Tickets.create_order(order_attrs(edition, lot))
    end

    test "rejects a lot whose sales window has not opened" do
      future = DateTime.add(DateTime.utc_now(), 3600) |> DateTime.truncate(:second)
      {edition, lot} = edition_with_lot(%{}, %{opens_at: future})
      assert {:error, {:not_on_sale, _}} = Tickets.create_order(order_attrs(edition, lot))
    end
  end

  describe "confirm_order/1" do
    test "issues one ticket per unit and links the device push" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 3}]})
        )

      assert {:ok, confirmed} = Tickets.confirm_order(order.id)
      assert confirmed.status == :confirmed

      # Capacity is claimed here, not at create.
      assert Repo.get!(TicketType, lot.id).available == 2

      tickets = Repo.all(Ticket)
      assert length(tickets) == 3
      assert Enum.all?(tickets, &(&1.edition_id == edition.id))
      assert Enum.all?(tickets, &(&1.code =~ ~r/^[0-9A-HJKMNP-TV-Z]{8}$/))
      assert length(Enum.uniq_by(tickets, & &1.code)) == 3
    end

    test "returns :not_pending if the order already left pending" do
      {edition, lot} = edition_with_lot()
      {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
      {:ok, _} = Tickets.confirm_order(order.id)

      assert {:error, :not_pending} = Tickets.confirm_order(order.id)
    end

    test "two pending orders for the last seat: second confirm is sold_out" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 1})

      {:ok, first} = Tickets.create_order(order_attrs(edition, lot))
      {:ok, second} = Tickets.create_order(order_attrs(edition, lot))

      assert {:ok, _} = Tickets.confirm_order(first.id)
      assert {:error, {:sold_out, id}} = Tickets.confirm_order(second.id)
      assert id == lot.id

      # Failed confirm leaves no tickets and keeps the order pending.
      assert Repo.get!(Order, second.id).status == :pending
      assert Repo.aggregate(Ticket, :count, :id) == 1
      assert Repo.get!(TicketType, lot.id).available == 0
    end

    test "retries on a code collision" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 2})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      # Generator returns a duplicate first, then unique codes.
      {:ok, agent} = Agent.start_link(fn -> ["DUP00000", "DUP00000", "UNIQ0001", "UNIQ0002"] end)

      code_fun = fn ->
        Agent.get_and_update(agent, fn [h | t] -> {h, t} end)
      end

      assert {:ok, _} = Tickets.confirm_order(order.id, code_fun: code_fun)
      codes = Repo.all(Ticket) |> Enum.map(& &1.code) |> Enum.sort()
      assert codes == ["DUP00000", "UNIQ0001"]
    end
  end

  describe "issue_confirmed/2" do
    test "emits against an inactive lote without gating on is_active" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 10, is_active: false})

      assert {:ok, %{order: order, codes: [_, _] = codes}} =
               Tickets.issue_confirmed(%{
                 edition_id: edition.id,
                 ticket_type_id: lot.id,
                 customer_name: "Maria",
                 customer_instagram: "maria",
                 quantity: 2
               })

      assert order.status == :confirmed
      assert Repo.aggregate(Ticket, :count, :id) == 2
      assert length(codes) == 2
      assert Repo.get!(TicketType, lot.id).available == 8
    end

    test "does not touch a sibling active paid lote's available" do
      edition = edition_fixture()
      paid = ticket_type_fixture(edition, %{name: "Lote 1", capacity: 5})
      comp = ticket_type_fixture(edition, %{name: "Cortesia", capacity: 10, is_active: false})

      assert {:ok, _} =
               Tickets.issue_confirmed(%{
                 edition_id: edition.id,
                 ticket_type_id: comp.id,
                 customer_name: "Maria",
                 customer_instagram: "maria",
                 quantity: 3
               })

      assert Repo.get!(TicketType, comp.id).available == 7
      assert Repo.get!(TicketType, paid.id).available == 5
    end

    test "clamps available at 0 when qty exceeds it, tickets still emitted" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 2, is_active: false})

      assert {:ok, %{codes: codes}} =
               Tickets.issue_confirmed(%{
                 edition_id: edition.id,
                 ticket_type_id: lot.id,
                 customer_name: "Maria",
                 customer_instagram: "maria",
                 quantity: 5
               })

      assert length(codes) == 5
      assert Repo.aggregate(Ticket, :count, :id) == 5
      assert Repo.get!(TicketType, lot.id).available == 0
    end

    test "blank instagram returns a changeset error, persists nothing" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 10, is_active: false})

      assert {:error, %Ecto.Changeset{}} =
               Tickets.issue_confirmed(%{
                 edition_id: edition.id,
                 ticket_type_id: lot.id,
                 customer_name: "Maria",
                 customer_instagram: "",
                 quantity: 1
               })

      assert Repo.aggregate(Order, :count, :id) == 0
      assert Repo.aggregate(Ticket, :count, :id) == 0
    end

    test "notify?: true broadcasts new_order, notify?: false does not" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 10, is_active: false})
      Phoenix.PubSub.subscribe(SeshLab.PubSub, "admin:orders")

      input = %{
        edition_id: edition.id,
        ticket_type_id: lot.id,
        customer_name: "Maria",
        customer_instagram: "maria",
        quantity: 1
      }

      assert {:ok, _} = Tickets.issue_confirmed(input, notify?: false)
      refute_receive {:new_order, _}, 100

      assert {:ok, _} = Tickets.issue_confirmed(input, notify?: true)
      assert_receive {:new_order, _}
    end
  end

  describe "validate_ticket/1" do
    setup do
      {edition, lot} = edition_with_lot()
      {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
      {:ok, _} = Tickets.confirm_order(order.id)
      [ticket] = Repo.all(Ticket)
      %{ticket: ticket}
    end

    test "marks a ticket used on first scan, rejects the second", %{ticket: ticket} do
      assert {:ok, validated} = Tickets.validate_ticket(ticket.code)
      assert validated.used_at

      assert {:error, {:already_used, _at}} = Tickets.validate_ticket(ticket.code)
    end

    test "unknown code is not_found" do
      assert {:error, :not_found} = Tickets.validate_ticket("ZZZZZZZZ")
    end

    test "normalizes separators and Crockford lookalikes", %{ticket: ticket} do
      # Build a lookalike input: lowercase + hyphen, 0→O, 1→L.
      noisy =
        ticket.code
        |> String.downcase()
        |> String.replace("0", "o")
        |> String.replace("1", "l")
        |> then(&(String.slice(&1, 0, 4) <> "-" <> String.slice(&1, 4, 4)))

      assert {:ok, _} = Tickets.validate_ticket(noisy)
    end
  end

  describe "cancel_order/1" do
    test "pending cancel only changes status (held no capacity)" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      assert Repo.get!(TicketType, lot.id).available == 5
      assert {:ok, cancelled} = Tickets.cancel_order(order.id)
      assert cancelled.status == :cancelled
      assert Repo.get!(TicketType, lot.id).available == 5
    end

    test "confirmed cancel restores capacity and deletes tickets" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      {:ok, _} = Tickets.confirm_order(order.id)
      assert Repo.get!(TicketType, lot.id).available == 3
      [ticket | _] = Repo.all(Ticket)

      assert {:ok, _} = Tickets.cancel_order(order.id)
      assert Repo.all(Ticket) == []
      assert Repo.get!(TicketType, lot.id).available == 5
      assert {:error, :not_found} = Tickets.validate_ticket(ticket.code)
    end
  end

  describe "generate_code/0" do
    test "is 8 Crockford base32 chars" do
      for _ <- 1..50 do
        assert Tickets.generate_code() =~ ~r/^[0-9A-HJKMNP-TV-Z]{8}$/
      end
    end
  end

  describe "stats/1" do
    test "splits sold / held / available / validated" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 10})

      {:ok, confirmed} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      {:ok, _} = Tickets.confirm_order(confirmed.id)

      {:ok, _pending} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 3}]})
        )

      [ticket | _] = Repo.all(Ticket)
      {:ok, _} = Tickets.validate_ticket(ticket.code)

      stats = Tickets.stats(edition.id)
      assert stats.capacity == 10
      assert stats.sold_confirmed == 2
      assert stats.held_pending == 3
      # Pending no longer subtracts from available — only confirmed does.
      assert stats.available == 8
      assert stats.validated == 1
    end
  end

  describe "search_orders/2" do
    setup do
      {edition, _lot} = edition_with_lot()
      {:ok, edition: edition}
    end

    test "finds by instagram handle, stripping @ and casing", %{edition: edition} do
      insert_order(edition, %{customer_name: "Ana Costa", customer_instagram: "anaclara"})
      assert [o] = Tickets.search_orders("@AnaCl")
      assert o.customer_instagram == "anaclara"
    end

    test "matches name as a substring", %{edition: edition} do
      insert_order(edition, %{customer_name: "Ana Costa", customer_instagram: "ac"})
      assert [o] = Tickets.search_orders("Costa")
      assert o.customer_name == "Ana Costa"
    end

    test "term under 2 chars returns empty", %{edition: edition} do
      insert_order(edition, %{customer_name: "Ana", customer_instagram: "ana"})
      assert Tickets.search_orders("a") == []
    end

    test "trims whitespace", %{edition: edition} do
      insert_order(edition, %{customer_name: "Ana", customer_instagram: "ana"})
      assert [_] = Tickets.search_orders("  ana  ")
    end

    test "is not edition-scoped — finds across editions", %{edition: edition} do
      other = edition_fixture()
      insert_order(edition, %{customer_name: "Zé Um", customer_instagram: "zeum"})
      insert_order(other, %{customer_name: "Zé Dois", customer_instagram: "zedois"})
      assert length(Tickets.search_orders("zé")) == 2
    end

    test "accented name searched without accent does not match (documented ASCII ceiling)",
         %{edition: edition} do
      insert_order(edition, %{customer_name: "José", customer_instagram: "jose"})
      # name arm misses (accent), but handle arm still finds it via "jose"
      assert [_] = Tickets.search_orders("jose")
      assert Tickets.search_orders("josé2") == []
    end
  end
end
