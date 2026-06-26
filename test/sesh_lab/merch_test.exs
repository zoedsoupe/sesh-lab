defmodule SeshLab.MerchTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Merch, Repo, Tickets}
  alias SeshLab.Editions.TicketType
  alias SeshLab.Merch.{Item, Unit}
  alias SeshLab.Tickets.{Order, Ticket}

  defp merch_item(attrs \\ %{}) do
    defaults = %{name: "Poster", price_cents: 2000, stock: 10}
    {:ok, item} = Merch.create_item(Map.merge(defaults, attrs))
    item
  end

  describe "catalog" do
    test "create_item valid -> active, available == stock" do
      assert {:ok, %Item{} = item} =
               Merch.create_item(%{name: "Poster", price_cents: 2000, stock: 10})

      assert item.is_active
      assert item.available == 10
      assert item.stock == 10
    end

    test "rejects blank name" do
      assert {:error, %Ecto.Changeset{}} =
               Merch.create_item(%{name: "", price_cents: 2000, stock: 10})
    end

    test "rejects negative price" do
      assert {:error, %Ecto.Changeset{}} =
               Merch.create_item(%{name: "Poster", price_cents: -1, stock: 10})
    end

    test "rejects negative stock" do
      assert {:error, %Ecto.Changeset{}} =
               Merch.create_item(%{name: "Poster", price_cents: 2000, stock: -1})
    end

    test "toggle_active flips is_active" do
      item = merch_item()
      assert {:ok, off} = Merch.toggle_active(item)
      refute off.is_active
      assert {:ok, on} = Merch.toggle_active(off)
      assert on.is_active
    end

    test "list_active_items excludes inactive" do
      active = merch_item(%{name: "Ativo"})
      inactive = merch_item(%{name: "Inativo"})
      {:ok, _} = Merch.toggle_active(inactive)

      ids = Merch.list_active_items() |> Enum.map(& &1.id)
      assert active.id in ids
      refute inactive.id in ids
    end

    test "editing stock propagates the delta to available" do
      item = merch_item(%{stock: 10})
      # Simulate 3 sold: available 7.
      {1, _} = Repo.update_all(from(m in Item, where: m.id == ^item.id), set: [available: 7])
      item = Merch.get_item!(item.id)

      assert {:ok, bumped} = Merch.update_item(item, %{stock: 15})
      assert bumped.stock == 15
      assert bumped.available == 12
    end

    test "update_item does not let a raw available param override server-derived value" do
      item = merch_item(%{stock: 10})
      {1, _} = Repo.update_all(from(m in Item, where: m.id == ^item.id), set: [available: 7])
      item = Merch.get_item!(item.id)

      # available is not castable; passing it must be ignored, derived from stock delta.
      assert {:ok, updated} = Merch.update_item(item, %{stock: 12, available: 999})
      assert updated.available == 9
    end
  end

  describe "mint on confirm" do
    test "confirming an order with a merch line mints one Unit per quantity and decrements available" do
      edition = edition_fixture()
      item = merch_item(%{stock: 10, price_cents: 2000})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 3}]
        })

      assert {:ok, _confirmed} = Tickets.confirm_order(order.id)

      units = Repo.all(Unit)
      assert length(units) == 3
      assert Enum.all?(units, &is_nil(&1.redeemed_at))
      assert Enum.all?(units, &(&1.merch_item_name_snapshot == item.name))
      assert Enum.all?(units, &(&1.sold_edition_id == edition.id))
      assert Enum.all?(units, &(&1.code =~ ~r/^[0-9A-HJKMNP-TV-Z]{8}$/))
      assert length(Enum.uniq_by(units, & &1.code)) == 3

      assert Merch.get_item!(item.id).available == 7
    end

    test "mixed order mints both tickets and units in one tx" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 5, price_cents: 1500})
      item = merch_item(%{stock: 10, price_cents: 2000})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [
            %{ticket_type_id: lot.id, quantity: 2},
            %{merch_item_id: item.id, quantity: 1}
          ]
        })

      assert {:ok, _} = Tickets.confirm_order(order.id)

      assert Repo.aggregate(Ticket, :count, :id) == 2
      assert Repo.aggregate(Unit, :count, :id) == 1
      assert Repo.get!(TicketType, lot.id).available == 3
      assert Merch.get_item!(item.id).available == 9
    end

    test "pure-merch order confirms without touching any TicketType.available" do
      edition = edition_fixture()
      lot = ticket_type_fixture(edition, %{capacity: 5})
      item = merch_item(%{stock: 10})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 2}]
        })

      assert {:ok, _} = Tickets.confirm_order(order.id)
      assert Repo.aggregate(Ticket, :count, :id) == 0
      assert Repo.aggregate(Unit, :count, :id) == 2
      assert Repo.get!(TicketType, lot.id).available == 5
    end

    test "injected colliding code_fun retries then succeeds" do
      edition = edition_fixture()
      item = merch_item(%{stock: 10})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 2}]
        })

      {:ok, agent} = Agent.start_link(fn -> ["DUP00000", "DUP00000", "UNIQ0001", "UNIQ0002"] end)
      code_fun = fn -> Agent.get_and_update(agent, fn [h | t] -> {h, t} end) end

      assert {:ok, _} = Tickets.confirm_order(order.id, code_fun: code_fun)
      codes = Repo.all(Unit) |> Enum.map(& &1.code) |> Enum.sort()
      assert codes == ["DUP00000", "UNIQ0001"]
    end
  end

  describe "stock at confirm" do
    test "confirming when available < requested rolls back, no units minted" do
      edition = edition_fixture()
      item = merch_item(%{stock: 10})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 2}]
        })

      # Drop available below the requested quantity after the (soft) create check.
      {1, _} = Repo.update_all(from(m in Item, where: m.id == ^item.id), set: [available: 1])

      assert {:error, {:merch_sold_out, id}} = Tickets.confirm_order(order.id)
      assert id == item.id
      assert Repo.aggregate(Unit, :count, :id) == 0
      assert Merch.get_item!(item.id).available == 1
      assert Repo.get!(Order, order.id).status == :pending
    end

    test "cancel of a confirmed merch order restores available and deletes units" do
      edition = edition_fixture()
      item = merch_item(%{stock: 10})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 3}]
        })

      {:ok, _} = Tickets.confirm_order(order.id)
      assert Merch.get_item!(item.id).available == 7
      assert Repo.aggregate(Unit, :count, :id) == 3

      assert {:ok, _} = Tickets.cancel_order(order.id)
      assert Merch.get_item!(item.id).available == 10
      assert Repo.aggregate(Unit, :count, :id) == 0
    end
  end

  describe "redeem_unit/1" do
    setup do
      edition = edition_fixture()
      item = merch_item(%{stock: 10})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [%{merch_item_id: item.id, quantity: 1}]
        })

      {:ok, _} = Tickets.confirm_order(order.id)
      [unit] = Repo.all(Unit)
      %{unit: unit}
    end

    test "first redeem sets redeemed_at, second is already_redeemed", %{unit: unit} do
      assert {:ok, redeemed} = Merch.redeem_unit(unit.code)
      assert redeemed.redeemed_at

      assert {:error, {:already_redeemed, _at}} = Merch.redeem_unit(unit.code)
    end

    test "unknown code is not_found" do
      assert {:error, :not_found} = Merch.redeem_unit("ZZZZZZZZ")
    end

    test "concurrent double-redeem: exactly one wins", %{unit: unit} do
      parent = self()

      results =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
            Merch.redeem_unit(unit.code)
          end)
        end)
        |> Task.await_many(5_000)

      oks = Enum.count(results, &match?({:ok, %Unit{}}, &1))
      redeemed = Enum.count(results, &match?({:error, {:already_redeemed, _}}, &1))

      assert oks == 1
      assert redeemed == 19
    end
  end

  describe "stats integrity" do
    test "stats/1 and stats_by_type/1 count only ticket quantities while revenue includes merch" do
      {edition, lot} = edition_with_lot(%{}, %{capacity: 10, price_cents: 1500})
      item = merch_item(%{stock: 10, price_cents: 2000})

      {:ok, order} =
        Tickets.create_order(%{
          edition_id: edition.id,
          customer_name: "Fulano",
          customer_instagram: "fulano",
          items: [
            %{ticket_type_id: lot.id, quantity: 2},
            %{merch_item_id: item.id, quantity: 3}
          ]
        })

      {:ok, confirmed} = Tickets.confirm_order(order.id)

      stats = Tickets.stats(edition.id)
      # Only ticket quantities count toward sold; merch excluded.
      assert stats.sold_confirmed == 2
      assert stats.available == 8
      # Revenue intentionally includes merch: 2 * 1500 + 3 * 2000 = 9000.
      assert stats.revenue_cents == confirmed.total_cents
      assert stats.revenue_cents == 9000

      by_type = Tickets.stats_by_type(edition.id)
      assert by_type[lot.id].sold == 2
    end

    test "XOR CHECK rejects a raw order_items insert with both FKs set" do
      {edition, lot} = edition_with_lot()
      item = merch_item()
      order = insert_order(edition)
      now = SeshLab.Clock.now_utc() |> DateTime.to_naive()

      assert_raise Exqlite.Error, fn ->
        Repo.insert_all(SeshLab.Tickets.OrderItem, [
          %{
            order_id: order.id,
            ticket_type_id: lot.id,
            ticket_type_name_snapshot: "Lote 1",
            merch_item_id: item.id,
            merch_item_name_snapshot: "Poster",
            quantity: 1,
            unit_price_cents: 1000,
            inserted_at: now
          }
        ])
      end
    end

    test "XOR CHECK rejects a raw order_items insert with neither FK set" do
      {edition, _lot} = edition_with_lot()
      order = insert_order(edition)
      now = SeshLab.Clock.now_utc() |> DateTime.to_naive()

      assert_raise Exqlite.Error, fn ->
        Repo.insert_all(SeshLab.Tickets.OrderItem, [
          %{
            order_id: order.id,
            quantity: 1,
            unit_price_cents: 1000,
            inserted_at: now
          }
        ])
      end
    end
  end
end
