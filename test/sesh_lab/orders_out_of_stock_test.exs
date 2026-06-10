defmodule SeshLab.OrdersOutOfStockTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.{Catalog.Product, Orders}

  setup do
    Phoenix.PubSub.subscribe(SeshLab.PubSub, "admin:orders")
    :ok
  end

  defp insert_product(attrs) do
    defaults = %{
      id: "test-brownie-#{System.unique_integer([:positive])}",
      name: "Brownie Teste",
      description: "test",
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

  defp order_attrs(product, qty) do
    %{
      customer_name: "Diana",
      customer_instagram: "diana",
      delivery_type: :retirada,
      payment_method: :pix,
      pix_key: "5522936192983",
      items: [%{product_id: product.id, quantity: qty}]
    }
  end

  test "broadcasts {:out_of_stock, pid, name} when post-decrement stock is 0" do
    product = insert_product(%{stock: 2})

    assert {:ok, _order} = Orders.create_order(order_attrs(product, 2))

    assert_receive {:new_order, _order_id}
    assert_receive {:out_of_stock, pid, name}
    assert pid == product.id
    assert name == product.name
  end

  test "does not broadcast :out_of_stock when stock remains" do
    product = insert_product(%{stock: 5})

    assert {:ok, _order} = Orders.create_order(order_attrs(product, 2))

    assert_receive {:new_order, _order_id}
    refute_receive {:out_of_stock, _, _}, 50
  end

  test "does not broadcast :out_of_stock for preorder items even when 'remaining' is nil" do
    product =
      insert_product(%{stock: 0, is_preorder: true, lead_time_days: 3})

    assert {:ok, _order} = Orders.create_order(order_attrs(product, 1))

    assert_receive {:new_order, _order_id}
    refute_receive {:out_of_stock, _, _}, 50
  end
end
