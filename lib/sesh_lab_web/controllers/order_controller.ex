defmodule SeshLabWeb.OrderController do
  use SeshLabWeb, :controller

  alias SeshLab.{Catalog, Coupons, Orders, Promos, Settings}
  alias SeshLab.Orders.Order
  alias SeshLab.Payments.Pix

  def new(conn, params) do
    changeset = Order.changeset(%Order{delivery_type: :retirada, payment_method: :pix}, %{})
    promo_param = params["promo"]
    promo = load_promo(promo_param)

    conn =
      if promo_param && is_nil(promo) do
        put_flash(conn, :error, "promo não encontrada ou inativa.")
      else
        conn
      end

    items = if promo, do: promo_items_map(promo), else: %{}

    render_form(conn, changeset, items, promo)
  end

  def create(conn, params) do
    order_params = Map.get(params, "order", %{})
    items_params = Map.get(params, "items", %{})
    promo = load_promo(params["promo_id"])

    case Orders.create_order(build_attrs(order_params, items_params, promo)) do
      {:ok, order} ->
        redirect(conn, to: ~p"/pedido/#{order.id}")

      {:error, {:out_of_stock, product_id}} ->
        product = Catalog.get_product!(product_id)

        conn
        |> put_flash(:error, "estoque insuficiente para #{product.name}.")
        |> render_form(Order.changeset(%Order{}, order_params), items_params, promo)

      {:error, :empty_cart} ->
        conn
        |> put_flash(:error, "escolha pelo menos uma unidade.")
        |> render_form(Order.changeset(%Order{}, order_params), items_params, promo)

      {:error, {:coupon, reason}} ->
        conn
        |> put_flash(:error, coupon_error(reason))
        |> render_form(Order.changeset(%Order{}, order_params), items_params, promo)

      {:error, %Ecto.Changeset{} = cs} ->
        render_form(conn, %{cs | action: :insert}, items_params, promo)

      {:error, _} ->
        conn
        |> put_flash(:error, "não foi possível registrar o pedido.")
        |> render_form(Order.changeset(%Order{}, order_params), items_params, promo)
    end
  end

  def show(conn, %{"id" => id}) do
    order = Orders.get_order!(id)

    render(conn, :show,
      order: order,
      pix: pix_payload(order),
      earned: Coupons.earned_for_order(order.id),
      high_demand: Settings.high_demand?()
    )
  end

  defp coupon_error(:not_found), do: "cupom não encontrado."
  defp coupon_error(:expired), do: "esse cupom expirou."
  defp coupon_error(:used), do: "esse cupom já foi usado."
  defp coupon_error(:inactive), do: "esse cupom não está mais ativo."
  defp coupon_error(:exhausted), do: "esse cupom atingiu o limite de usos."
  defp coupon_error(:wrong_customer), do: "esse cupom é de outro cliente."
  defp coupon_error(:coupon_taken), do: "esse cupom acabou de ser usado. tente outro."
  defp coupon_error(:no_stacking), do: "cupom não vale em promoções."

  defp coupon_error({:min_order, cents}),
    do: "esse cupom exige pedido mínimo de #{SeshLabWeb.CoreComponents.money(cents)}."

  defp coupon_error(_), do: "cupom inválido."

  # Static shell — the list is rendered client-side from localStorage
  # (assets/js/orders.js). No DB query, no PII server-side.
  def history(conn, _params) do
    render(conn, :history, page_title: "meus pedidos")
  end

  defp render_form(conn, changeset, items, promo) do
    products =
      if promo do
        promo.items
        |> Enum.map(& &1.product)
        |> Enum.reject(&is_nil/1)
      else
        Catalog.list_active_products()
        |> Enum.filter(&(&1.is_preorder or &1.stock > 0))
      end

    render(conn, :new,
      changeset: changeset,
      products: products,
      items: normalize_items_param(items),
      promo: promo,
      page_title: if(promo, do: "pedido — #{promo.name}", else: "pedido")
    )
  end

  defp build_attrs(order_params, items_params, promo) do
    items =
      items_params
      |> Enum.map(fn {pid, qty} -> %{product_id: pid, quantity: qty} end)
      |> Enum.reject(&(&1.quantity in ["", "0", 0, nil]))

    order_params
    |> Map.put("items", items)
    |> Map.put("pix_key", Application.fetch_env!(:sesh_lab, :pix)[:key])
    |> Map.put("status", "pending")
    |> maybe_apply_promo(promo)
  end

  defp maybe_apply_promo(attrs, nil), do: attrs

  defp maybe_apply_promo(attrs, promo) do
    attrs
    |> Map.put("promo_id", promo.id)
    |> Map.put("promo_total_cents", promo.total_cents)
  end

  defp load_promo(nil), do: nil
  defp load_promo(""), do: nil

  defp load_promo(id) when is_binary(id) do
    case Promos.get(id) do
      %{is_active: true} = promo -> promo
      _ -> nil
    end
  end

  defp promo_items_map(promo) do
    Map.new(promo.items, fn item -> {item.product_id, to_string(item.quantity)} end)
  end

  defp normalize_items_param(items) when is_map(items), do: items
  defp normalize_items_param(_), do: %{}

  defp pix_payload(%Order{payment_method: :pix, status: :pending} = order) do
    cfg = Application.fetch_env!(:sesh_lab, :pix)

    emv =
      Pix.build(
        pix_key: order.pix_key || cfg[:key],
        amount_cents: order.total_cents,
        merchant_name: cfg[:merchant_name],
        merchant_city: cfg[:merchant_city],
        txid: order.id |> String.replace("-", "") |> String.slice(0, 25)
      )

    %{emv: emv, svg: Pix.to_svg(emv)}
  end

  defp pix_payload(_), do: nil
end
