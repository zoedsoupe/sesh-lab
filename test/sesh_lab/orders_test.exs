defmodule SeshLab.OrdersTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.{Catalog.Product, Coupons, Orders}
  alias SeshLab.Orders.Order

  defp insert_product(attrs) do
    defaults = %{
      name: "Brownie",
      unit_label: "un",
      unit_price_cents: 1000,
      stock: 10,
      is_active: true,
      is_preorder: false
    }

    %Product{}
    |> Product.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp base_attrs(items) do
    %{
      customer_name: "Diana",
      customer_instagram: "diana",
      delivery_type: :retirada,
      payment_method: :pix,
      pix_key: "5522936192983",
      items: items
    }
  end

  describe "create_order/1" do
    test "creates an order with item snapshots and computed total" do
      p1 = insert_product(%{id: "brownie", name: "Brownie", unit_price_cents: 1000, stock: 10})
      p2 = insert_product(%{id: "coracao", name: "Coração", unit_price_cents: 500, stock: 10})

      attrs =
        base_attrs([
          %{product_id: "brownie", quantity: 2},
          %{product_id: "coracao", quantity: 3}
        ])

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.total_cents == 2 * 1000 + 3 * 500
      assert order.status == :pending

      order = Orders.get_order!(order.id)
      assert length(order.items) == 2

      items_by_pid = Map.new(order.items, &{&1.product_id, &1})
      assert items_by_pid["brownie"].product_name_snapshot == "Brownie"
      assert items_by_pid["brownie"].unit_price_cents == 1000
      assert items_by_pid["brownie"].quantity == 2
      assert items_by_pid["coracao"].unit_price_cents == 500

      # Stock decremented
      assert Repo.get!(Product, p1.id).stock == 8
      assert Repo.get!(Product, p2.id).stock == 7
    end

    test "freezes price snapshot — later product price change does NOT mutate item" do
      p = insert_product(%{id: "brownie", name: "Brownie", unit_price_cents: 1000, stock: 5})
      attrs = base_attrs([%{product_id: p.id, quantity: 1}])

      assert {:ok, order} = Orders.create_order(attrs)

      p
      |> Product.admin_changeset(%{unit_price_cents: 9999, name: "Renamed"})
      |> Repo.update!()

      [item] = Orders.get_order!(order.id).items
      assert item.unit_price_cents == 1000
      assert item.product_name_snapshot == "Brownie"
    end

    test "returns {:error, {:out_of_stock, pid}} and rolls back when insufficient" do
      p = insert_product(%{id: "brownie", name: "Brownie", stock: 1})
      attrs = base_attrs([%{product_id: p.id, quantity: 5}])

      assert {:error, {:out_of_stock, "brownie"}} = Orders.create_order(attrs)
      # Stock untouched.
      assert Repo.get!(Product, p.id).stock == 1
      # No order persisted.
      assert Repo.aggregate(Order, :count, :id) == 0
    end

    test "rejects unknown products" do
      attrs = base_attrs([%{product_id: "nope", quantity: 1}])
      assert {:error, {:unknown_product, "nope"}} = Orders.create_order(attrs)
    end

    test "rejects empty cart" do
      attrs = base_attrs([])
      assert {:error, :empty_cart} = Orders.create_order(attrs)
    end

    test "skips items with quantity 0 (treated as empty cart if all are 0)" do
      _p = insert_product(%{id: "brownie", name: "Brownie"})
      attrs = base_attrs([%{product_id: "brownie", quantity: 0}])
      assert {:error, :empty_cart} = Orders.create_order(attrs)
    end

    test "preorder items skip stock check entirely" do
      p =
        insert_product(%{
          id: "encomenda",
          name: "Encomenda",
          is_preorder: true,
          lead_time_days: 5,
          stock: 0
        })

      attrs = base_attrs([%{product_id: p.id, quantity: 3}])
      assert {:ok, order} = Orders.create_order(attrs)
      assert Repo.get!(Product, p.id).stock == 0

      [item] = Orders.get_order!(order.id).items
      assert item.lead_time_days_snapshot == 5
    end

    test "validates required order fields via Ecto changeset" do
      _p = insert_product(%{id: "brownie", name: "Brownie"})

      attrs = %{
        items: [%{product_id: "brownie", quantity: 1}],
        delivery_type: :retirada,
        payment_method: :pix,
        pix_key: "x"
      }

      assert {:error, %Ecto.Changeset{} = cs} = Orders.create_order(attrs)
      assert "can't be blank" in errors_on(cs).customer_name
    end

    test "requires address when delivery_type is not :retirada" do
      _p = insert_product(%{id: "brownie", name: "Brownie"})

      attrs =
        %{
          customer_name: "Diana",
          customer_instagram: "diana",
          delivery_type: :envio,
          payment_method: :pix,
          pix_key: "x",
          items: [%{product_id: "brownie", quantity: 1}]
        }

      assert {:error, cs} = Orders.create_order(attrs)
      assert "can't be blank" in errors_on(cs).address
    end
  end

  describe "create_order/1 with coupons" do
    setup do
      insert_product(%{id: "brownie", name: "Brownie", unit_price_cents: 1000, stock: 20})
      :ok
    end

    defp public_coupon(code, kind, value) do
      {:ok, _} =
        Coupons.create_public_coupon(%{
          "code" => code,
          "discount_kind" => to_string(kind),
          "discount_value" => to_string(value)
        })
    end

    test "redeems a public coupon and applies the discount" do
      public_coupon("TEN", :percent, 10)

      attrs =
        base_attrs([%{product_id: "brownie", quantity: 5}]) |> Map.put(:coupon_code, "TEN")

      assert {:ok, order} = Orders.create_order(attrs)
      assert order.total_cents == 5000 - 500
      assert order.discount_cents == 500
      assert order.coupon_code == "TEN"
      assert Coupons.get_by_code("TEN").uses_count == 1
    end

    test "lowercase code input is matched" do
      public_coupon("SAVE5", :fixed, 300)

      attrs =
        base_attrs([%{product_id: "brownie", quantity: 2}]) |> Map.put(:coupon_code, "save5")

      assert {:ok, order} = Orders.create_order(attrs)
      assert order.discount_cents == 300
    end

    test "rejects an unknown coupon" do
      attrs =
        base_attrs([%{product_id: "brownie", quantity: 1}]) |> Map.put(:coupon_code, "NOPE")

      assert {:error, {:coupon, :not_found}} = Orders.create_order(attrs)
    end

    test "coupons do not stack on promos" do
      public_coupon("TEN", :percent, 10)

      attrs =
        base_attrs([%{product_id: "brownie", quantity: 1}])
        |> Map.put(:promo_total_cents, 700)
        |> Map.put(:coupon_code, "TEN")

      assert {:error, {:coupon, :no_stacking}} = Orders.create_order(attrs)
    end

    test "a client cannot inject a fake discount via params" do
      attrs =
        base_attrs([%{product_id: "brownie", quantity: 1}])
        |> Map.put(:discount_cents, 999)

      assert {:ok, order} = Orders.create_order(attrs)
      assert order.discount_cents == 0
      assert order.total_cents == 1000
    end
  end

  describe "confirm_order/1" do
    test "marks the order as :confirmed and broadcasts" do
      Phoenix.PubSub.subscribe(SeshLab.PubSub, "admin:orders")
      _p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
      {:ok, o} = Orders.create_order(base_attrs([%{product_id: "brownie", quantity: 1}]))
      assert_receive {:new_order, _}

      assert {:ok, %Order{status: :confirmed}} = Orders.confirm_order(o.id)
      assert_receive {:order_updated, _}
    end

    test "confirming an already-confirmed order is idempotent" do
      _p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
      {:ok, o} = Orders.create_order(base_attrs([%{product_id: "brownie", quantity: 1}]))

      {:ok, _} = Orders.confirm_order(o.id)
      assert {:ok, %Order{status: :confirmed}} = Orders.confirm_order(o.id)
    end
  end

  describe "cancel_order/1" do
    test "restores stock when the order was pending" do
      p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
      {:ok, o} = Orders.create_order(base_attrs([%{product_id: p.id, quantity: 3}]))
      assert Repo.get!(Product, p.id).stock == 2

      assert {:ok, %Order{status: :cancelled}} = Orders.cancel_order(o.id)
      assert Repo.get!(Product, p.id).stock == 5
    end

    test "does NOT restore stock when the order was already confirmed" do
      p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
      {:ok, o} = Orders.create_order(base_attrs([%{product_id: p.id, quantity: 3}]))
      {:ok, _} = Orders.confirm_order(o.id)
      assert Repo.get!(Product, p.id).stock == 2

      assert {:ok, %Order{status: :cancelled}} = Orders.cancel_order(o.id)
      assert Repo.get!(Product, p.id).stock == 2
    end

    test "preorder items never restore stock (none was reserved)" do
      p =
        insert_product(%{
          id: "encomenda",
          name: "Encomenda",
          is_preorder: true,
          lead_time_days: 5,
          stock: 0
        })

      {:ok, o} = Orders.create_order(base_attrs([%{product_id: p.id, quantity: 3}]))
      assert {:ok, _} = Orders.cancel_order(o.id)
      assert Repo.get!(Product, p.id).stock == 0
    end
  end

  describe "list_pending/0 + list_recent/1" do
    test "pending excludes other statuses; recent caps the count" do
      _p = insert_product(%{id: "brownie", name: "Brownie", stock: 100})
      attrs = base_attrs([%{product_id: "brownie", quantity: 1}])

      {:ok, o1} = Orders.create_order(attrs)
      {:ok, o2} = Orders.create_order(attrs)
      {:ok, _} = Orders.confirm_order(o2.id)

      pending_ids = Orders.list_pending() |> Enum.map(& &1.id)
      assert o1.id in pending_ids
      refute o2.id in pending_ids

      assert length(Orders.list_recent(1)) == 1
      assert length(Orders.list_recent(10)) == 2
    end
  end

  describe "max_lead_time_days/1" do
    test "returns max across preorder items, nil if none" do
      _p1 =
        insert_product(%{
          id: "fast",
          name: "Fast",
          is_preorder: true,
          lead_time_days: 2,
          stock: 0
        })

      _p2 =
        insert_product(%{
          id: "slow",
          name: "Slow",
          is_preorder: true,
          lead_time_days: 7,
          stock: 0
        })

      {:ok, o} =
        Orders.create_order(
          base_attrs([
            %{product_id: "fast", quantity: 1},
            %{product_id: "slow", quantity: 1}
          ])
        )

      assert Orders.max_lead_time_days(Orders.get_order!(o.id)) == 7
    end

    test "returns nil for pronta-entrega-only orders" do
      _p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
      {:ok, o} = Orders.create_order(base_attrs([%{product_id: "brownie", quantity: 1}]))
      assert Orders.max_lead_time_days(Orders.get_order!(o.id)) == nil
    end
  end
end
