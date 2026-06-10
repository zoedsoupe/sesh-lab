defmodule SeshLabWeb.OrderController do
  use SeshLabWeb, :controller

  alias SeshLab.{Clock, Coupons, Editions, Tickets}
  alias SeshLab.Editions.{Edition, TicketType}
  alias SeshLab.Tickets.Order
  alias SeshLab.Payments.Pix

  def new(conn, _params) do
    case Editions.current_edition() do
      nil ->
        conn
        |> put_flash(:error, "nenhuma edição com ingressos à venda agora.")
        |> redirect(to: ~p"/")

      %Edition{} = edition ->
        render_form(conn, edition, Order.changeset(%Order{}, %{}), %{})
    end
  end

  def create(conn, params) do
    order_params = Map.get(params, "order", %{})
    items_params = Map.get(params, "items", %{})

    case Editions.current_edition() do
      nil ->
        conn
        |> put_flash(:error, "nenhuma edição com ingressos à venda agora.")
        |> redirect(to: ~p"/")

      %Edition{} = edition ->
        case Tickets.create_order(build_attrs(edition, order_params, items_params)) do
          {:ok, order} ->
            redirect(conn, to: ~p"/compra/#{order.id}")

          {:error, {:sold_out, type_id}} ->
            type = Editions.get_ticket_type!(type_id)

            conn
            |> put_flash(:error, "ingressos esgotados para #{type.name}.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:not_on_sale, _id}} ->
            conn
            |> put_flash(:error, "esse lote não está mais à venda.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, :empty_cart} ->
            conn
            |> put_flash(:error, "escolha pelo menos um ingresso.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:coupon, reason}} ->
            conn
            |> put_flash(:error, coupon_error(reason))
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, %Ecto.Changeset{} = cs} ->
            render_form(conn, reload(edition), %{cs | action: :insert}, items_params)

          {:error, _} ->
            conn
            |> put_flash(:error, "não foi possível registrar o pedido.")
            |> render_form(reload(edition), changeset(order_params), items_params)
        end
    end
  end

  def show(conn, %{"id" => id}) do
    order = Tickets.get_order!(id)
    edition = Editions.get_edition!(order.edition_id)

    conn
    |> assign(:accent, edition.accent_color)
    |> render(:show,
      order: order,
      edition: edition,
      pix: pix_payload(order),
      earned: Coupons.earned_for_order(order.id),
      page_title: "ingresso"
    )
  end

  # Static shell — the list is rendered client-side from localStorage
  # (assets/js/orders.js). No DB query, no PII server-side.
  def history(conn, _params) do
    render(conn, :history, page_title: "meus ingressos")
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp reload(%Edition{id: id}), do: Editions.get_edition!(id)

  defp changeset(order_params), do: Order.changeset(%Order{}, order_params)

  defp render_form(conn, edition, changeset, items) do
    conn
    |> assign(:accent, edition.accent_color)
    |> render(:new,
      edition: edition,
      changeset: changeset,
      lots: lots_on_sale(edition),
      items: normalize_items_param(items),
      page_title: "comprar — #{edition.name}"
    )
  end

  defp lots_on_sale(%Edition{ticket_types: types}) do
    now = Clock.now_utc()

    types
    |> Enum.filter(&(TicketType.on_sale?(&1, now) and &1.available > 0))
    |> Enum.sort_by(& &1.position)
  end

  defp build_attrs(edition, order_params, items_params) do
    items =
      items_params
      |> Enum.map(fn {type_id, qty} -> %{ticket_type_id: type_id, quantity: qty} end)
      |> Enum.reject(&(&1.quantity in ["", "0", 0, nil]))

    order_params
    |> Map.put("edition_id", edition.id)
    |> Map.put("items", items)
    |> Map.put("pix_key", Application.fetch_env!(:sesh_lab, :pix)[:key])
    |> Map.put("status", "pending")
  end

  defp normalize_items_param(items) when is_map(items), do: items
  defp normalize_items_param(_), do: %{}

  defp coupon_error(:not_found), do: "cupom não encontrado."
  defp coupon_error(:expired), do: "esse cupom expirou."
  defp coupon_error(:used), do: "esse cupom já foi usado."
  defp coupon_error(:inactive), do: "esse cupom não está mais ativo."
  defp coupon_error(:exhausted), do: "esse cupom atingiu o limite de usos."
  defp coupon_error(:wrong_customer), do: "esse cupom é de outra pessoa."
  defp coupon_error(:coupon_taken), do: "esse cupom acabou de ser usado. tente outro."

  defp coupon_error({:min_order, cents}),
    do: "esse cupom exige pedido mínimo de #{SeshLabWeb.CoreComponents.money(cents)}."

  defp coupon_error(_), do: "cupom inválido."

  defp pix_payload(%Order{status: :pending} = order) do
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
