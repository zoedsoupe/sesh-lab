defmodule SeshLabWeb.OrderControllerTest do
  use SeshLabWeb.ConnCase, async: false

  alias SeshLab.{Catalog.Product, Repo, Settings}

  defp insert_product(attrs) do
    defaults = %{
      name: "Brownie",
      unit_label: "un",
      unit_price_cents: 1000,
      stock: 5,
      is_active: true,
      is_preorder: false
    }

    %Product{}
    |> Product.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp form_params(items, overrides \\ %{}) do
    order =
      Map.merge(
        %{
          "customer_name" => "Diana",
          "customer_instagram" => "diana",
          "delivery_type" => "retirada",
          "payment_method" => "pix"
        },
        overrides
      )

    %{"order" => order, "items" => items}
  end

  describe "GET /pedido" do
    test "renders the order form with active products", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 3})
      insert_product(%{id: "inactive", name: "Inactive", is_active: false})

      resp = conn |> get(~p"/pedido") |> html_response(200)
      assert resp =~ "Brownie"
      refute resp =~ "Inactive"
    end

    test "excludes pronta-entrega products with zero stock", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 0})

      resp = conn |> get(~p"/pedido") |> html_response(200)
      refute resp =~ "Brownie"
    end

    test "includes preorder products regardless of stock", %{conn: conn} do
      insert_product(%{
        id: "encomenda",
        name: "EncomendaTeste",
        is_preorder: true,
        lead_time_days: 5,
        stock: 0
      })

      resp = conn |> get(~p"/pedido") |> html_response(200)
      assert resp =~ "EncomendaTeste"
    end
  end

  describe "POST /pedido" do
    test "creates an order and redirects to /pedido/:id", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      params = form_params(%{"brownie" => "2"})
      conn = post(conn, ~p"/pedido", params)

      assert %{id: order_id} = redirected_params(conn)
      assert redirected_to(conn) =~ "/pedido/" <> order_id
    end

    test "re-renders form with flash on out_of_stock", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 1})

      params = form_params(%{"brownie" => "5"})
      conn = post(conn, ~p"/pedido", params)

      assert html_response(conn, 200)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "estoque insuficiente"
    end

    test "re-renders form with flash when cart is empty", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      params = form_params(%{"brownie" => "0"})
      conn = post(conn, ~p"/pedido", params)

      assert html_response(conn, 200)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "pelo menos uma unidade"
    end

    test "re-renders form when changeset is invalid", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      params =
        form_params(%{"brownie" => "1"}, %{
          "customer_name" => "",
          "customer_instagram" => ""
        })

      conn = post(conn, ~p"/pedido", params)
      assert html_response(conn, 200)
    end
  end

  describe "GET /pedido/:id" do
    test "shows order details with PIX QR code", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      create_conn = post(build_conn(), ~p"/pedido", form_params(%{"brownie" => "2"}))
      %{id: order_id} = redirected_params(create_conn)

      resp = conn |> get(~p"/pedido/#{order_id}") |> html_response(200)
      assert resp =~ "Brownie"
      assert resp =~ "R$ 20,00"
      assert resp =~ "aguardando"
      assert resp =~ "<svg"
    end

    test "404s for unknown order id" do
      assert_error_sent 404, fn ->
        get(build_conn(), ~p"/pedido/00000000-0000-0000-0000-000000000000")
      end
    end

    test "shows high-demand banner when flag is on", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      create_conn = post(build_conn(), ~p"/pedido", form_params(%{"brownie" => "2"}))
      %{id: order_id} = redirected_params(create_conn)

      {:ok, _} = Settings.set_high_demand(true)
      on_exit(fn -> Settings.set_high_demand(false) end)

      resp = conn |> get(~p"/pedido/#{order_id}") |> html_response(200)
      assert resp =~ "Alta Demanda"
      assert resp =~ "alert--demand"
    end

    test "hides high-demand banner when flag is off", %{conn: conn} do
      insert_product(%{id: "brownie", name: "Brownie", stock: 5})

      create_conn = post(build_conn(), ~p"/pedido", form_params(%{"brownie" => "2"}))
      %{id: order_id} = redirected_params(create_conn)

      {:ok, _} = Settings.set_high_demand(false)

      resp = conn |> get(~p"/pedido/#{order_id}") |> html_response(200)
      refute resp =~ "alert--demand"
    end
  end
end
