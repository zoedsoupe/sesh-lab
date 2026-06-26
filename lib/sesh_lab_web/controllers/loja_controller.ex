defmodule SeshLabWeb.LojaController do
  @moduledoc """
  Loja de merch standalone. Vende produtos direto, sem ingresso e sem edicao,
  a qualquer hora. Pedido criado tem edition_id nil (pure-merch) e cai no fluxo
  PIX existente (/compra/:id). Sem cupom na v1.

  Pedidos da loja nao aparecem no painel por edicao (edition_id nil); ficam no
  historico global /admin/buscar e no detalhe /admin/pedidos/:id.
  """
  use SeshLabWeb, :controller

  alias SeshLab.{Merch, Tickets}
  alias SeshLab.Tickets.Order

  def index(conn, _params) do
    conn
    |> assign(:storefront, true)
    |> assign(:seo_description, "Produtos da SESH. Posters, adesivos e mais.")
    |> assign(:seo_type, "website")
    |> render(:index,
      merch: Merch.list_active_items(),
      changeset: Order.changeset(%Order{}, %{}),
      items: %{},
      page_title: "Loja"
    )
  end

  def create(conn, params) do
    order_params = Map.get(params, "order", %{})
    merch_params = Map.get(params, "merch", %{})

    case Tickets.create_order(build_attrs(order_params, merch_params)) do
      {:ok, order} ->
        redirect(conn, to: ~p"/compra/#{order.id}")

      {:error, :empty_cart} ->
        render_error(conn, order_params, merch_params, "Escolha pelo menos um produto.")

      {:error, {:merch_sold_out, _id}} ->
        render_error(conn, order_params, merch_params, "Produto esgotado.")

      {:error, {:merch_unavailable, _id}} ->
        render_error(conn, order_params, merch_params, "Produto indisponivel.")

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> assign(:storefront, true)
        |> assign(:seo_description, "Produtos da SESH. Posters, adesivos e mais.")
        |> assign(:seo_type, "website")
        |> render(:index,
          merch: Merch.list_active_items(),
          changeset: %{cs | action: :insert},
          items: merch_params,
          page_title: "Loja"
        )

      {:error, _} ->
        render_error(conn, order_params, merch_params, "Nao foi possivel registrar o pedido.")
    end
  end

  defp build_attrs(order_params, merch_params) do
    merch_lines =
      merch_params
      |> Enum.map(fn {id, qty} -> %{merch_item_id: id, quantity: qty} end)
      |> Enum.reject(&(&1.quantity in ["", "0", 0, nil]))

    order_params
    |> Map.put("edition_id", nil)
    |> Map.put("items", merch_lines)
    |> Map.put("pix_key", Application.fetch_env!(:sesh_lab, :pix)[:key])
    |> Map.put("status", "pending")
  end

  defp render_error(conn, order_params, merch_params, msg) do
    conn
    |> assign(:storefront, true)
    |> assign(:seo_description, "Produtos da SESH. Posters, adesivos e mais.")
    |> assign(:seo_type, "website")
    |> put_flash(:error, msg)
    |> render(:index,
      merch: Merch.list_active_items(),
      changeset: Order.changeset(%Order{}, order_params),
      items: merch_params,
      page_title: "Loja"
    )
  end
end
