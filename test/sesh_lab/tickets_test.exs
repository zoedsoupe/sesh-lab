defmodule SeshLab.TicketsTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Repo, Tickets}
  alias SeshLab.Editions.TicketType
  alias SeshLab.Tickets.{Order, Ticket}

  describe "create_order/1" do
    test "reserves capacity and snapshots items" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5, price_cents: 1500})

      assert {:ok, %Order{} = order} =
               Tickets.create_order(
                 order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
               )

      assert order.status == :pending
      assert order.total_cents == 3000
      assert order.expires_at
      assert Repo.get!(TicketType, lot.id).available == 3

      [item] = Repo.preload(order, :items).items
      assert item.quantity == 2
      assert item.unit_price_cents == 1500
      assert item.ticket_type_name_snapshot == lot.name
    end

    test "rejects empty cart" do
      {edition, _lot} = edition_with_lot()
      assert {:error, :empty_cart} = Tickets.create_order(%{edition_id: edition.id, items: []})
    end

    test "rejects quantity beyond capacity" do
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
    test "pending cancel restores capacity" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      assert Repo.get!(TicketType, lot.id).available == 3
      assert {:ok, _} = Tickets.cancel_order(order.id)
      assert Repo.get!(TicketType, lot.id).available == 5
    end

    test "confirmed cancel deletes tickets so the door reads not_found" do
      {edition, lot} = edition_with_lot()
      {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
      {:ok, _} = Tickets.confirm_order(order.id)
      [ticket] = Repo.all(Ticket)

      assert {:ok, _} = Tickets.cancel_order(order.id)
      assert Repo.all(Ticket) == []
      assert {:error, :not_found} = Tickets.validate_ticket(ticket.code)
    end
  end

  describe "expire_pending/1" do
    test "expires stale pending orders and restores capacity" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5})

      {:ok, order} =
        Tickets.create_order(
          order_attrs(edition, lot, %{items: [%{ticket_type_id: lot.id, quantity: 2}]})
        )

      # Force the order past its TTL.
      past = DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)
      Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [expires_at: past])

      assert Tickets.expire_pending() == 1
      assert Repo.get!(Order, order.id).status == :expired
      assert Repo.get!(TicketType, lot.id).available == 5
    end

    test "does not touch a confirmed order even if expires_at is in the past" do
      {edition, lot} = edition_with_lot()
      {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
      {:ok, _} = Tickets.confirm_order(order.id)

      past = DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)
      Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [expires_at: past])

      assert Tickets.expire_pending() == 0
      assert Repo.get!(Order, order.id).status == :confirmed
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
      assert stats.available == 5
      assert stats.validated == 1
    end
  end
end
