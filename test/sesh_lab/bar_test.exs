defmodule SeshLab.BarTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Bar, Merch}
  alias SeshLab.Merch.Item

  defp counter_item(attrs) do
    base = %{kind: :counter, price_cents: 500}
    {:ok, item} = Merch.create_item(Map.merge(base, attrs))
    item
  end

  defp reload(%Item{id: id}), do: Merch.get_item!(id)

  describe "record_sale/3" do
    test "cash sale: totals, snapshots line, decrements tracked stock" do
      water = counter_item(%{name: "Água", price_cents: 500, track_stock: true, stock: 5})
      ed = edition_fixture()

      assert {:ok, sale} = Bar.record_sale(ed.id, :cash, %{water.id => "3"})
      assert sale.payment_method == :cash
      assert sale.total_cents == 1500

      sale = Repo.preload(sale, :items)
      assert [line] = sale.items
      assert line.name_snapshot == "Água"
      assert line.quantity == 3
      assert line.unit_price_cents == 500

      assert reload(water).available == 2
    end

    test "untracked item sells beyond any count, stock untouched" do
      cig = counter_item(%{name: "Cigarro", price_cents: 1500, track_stock: false})

      assert {:ok, sale} = Bar.record_sale(nil, :pix, %{cig.id => 99})
      assert sale.total_cents == 99 * 1500
      assert reload(cig).available == 0
    end

    test "tracked item over available is rejected, no partial commit" do
      water = counter_item(%{name: "Água", track_stock: true, stock: 2})

      assert {:error, {:sold_out, "Água"}} = Bar.record_sale(nil, :cash, %{water.id => "3"})
      assert reload(water).available == 2
    end

    test "empty cart (all zero) is rejected" do
      water = counter_item(%{name: "Água", track_stock: true, stock: 2})
      assert {:error, :empty_cart} = Bar.record_sale(nil, :cash, %{water.id => "0"})
    end

    test "ignores unknown ids" do
      assert {:error, :empty_cart} = Bar.record_sale(nil, :cash, %{Ecto.UUID.generate() => "1"})
    end
  end

  describe "stats/1" do
    test "splits cash/pix, counts sales, ranks top items" do
      ed = edition_fixture()
      water = counter_item(%{name: "Água", price_cents: 500, track_stock: false})
      beer = counter_item(%{name: "Cerveja", price_cents: 1000, track_stock: false})

      {:ok, _} = Bar.record_sale(ed.id, :cash, %{water.id => 2, beer.id => 1})
      {:ok, _} = Bar.record_sale(ed.id, :pix, %{beer.id => 3})

      stats = Bar.stats(ed.id)
      assert stats.count == 2
      assert stats.cash_cents == 2000
      assert stats.pix_cents == 3000
      assert stats.total_cents == 5000

      assert [%{name: "Cerveja", qty: 4, cents: 4000} | _] = stats.top_items
    end
  end
end
