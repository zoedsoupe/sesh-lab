defmodule SeshLab.OrdersRaceTest do
  @moduledoc """
  Concurrency guarantee: stock decrement uses an atomic `update_all` with
  `where stock >= quantity`. SQLite's global write lock makes this trivially
  safe; the test still exercises the contract — when N callers race over a
  product with K < N units, exactly K orders succeed and the rest cleanly
  fail with `{:out_of_stock, pid}` (no over-sell, no partial rows).
  """

  use SeshLab.DataCase, async: false

  alias SeshLab.{Catalog.Product, Orders}
  alias SeshLab.Orders.{Order, OrderItem}

  defp insert_product(attrs) do
    defaults = %{
      name: "Brownie",
      unit_label: "un",
      unit_price_cents: 1000,
      stock: 1,
      is_active: true,
      is_preorder: false
    }

    %Product{}
    |> Product.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp order_attrs(pid) do
    %{
      customer_name: "Diana",
      customer_instagram: "diana",
      delivery_type: :retirada,
      payment_method: :pix,
      pix_key: "x",
      items: [%{product_id: pid, quantity: 1}]
    }
  end

  test "N concurrent orders over K stock: exactly K succeed, N-K fail with out_of_stock" do
    stock = 3
    callers = 10

    p = insert_product(%{id: "brownie", name: "Brownie", stock: stock})
    parent = self()

    1..callers
    |> Enum.map(fn _i ->
      Task.async(fn ->
        # Share the SQL sandbox connection with the parent process.
        Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
        Orders.create_order(order_attrs(p.id))
      end)
    end)
    |> Task.await_many(5_000)
    |> then(fn results ->
      successes = Enum.count(results, &match?({:ok, %Order{}}, &1))
      failures = Enum.count(results, &match?({:error, {:out_of_stock, "brownie"}}, &1))

      assert successes == stock
      assert failures == callers - stock
    end)

    # Final stock = 0, exactly `stock` orders + `stock` items persisted.
    assert Repo.get!(Product, p.id).stock == 0
    assert Repo.aggregate(Order, :count, :id) == stock
    assert Repo.aggregate(OrderItem, :count, :id) == stock
  end

  test "concurrent orders never go below zero (no over-sell)" do
    p = insert_product(%{id: "brownie", name: "Brownie", stock: 5})
    parent = self()

    1..20
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
        Orders.create_order(order_attrs(p.id))
      end)
    end)
    |> Task.await_many(5_000)

    assert Repo.get!(Product, p.id).stock == 0
  end
end
