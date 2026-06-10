defmodule SeshLabWeb.Admin.OrderShowLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Orders
  alias SeshLabWeb.Instagram

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Orders.get_order!(id)
    {:ok, assign(socket, order: order, page_title: "pedido")}
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    {:ok, order} = Orders.confirm_order(socket.assigns.order.id)
    {:noreply, socket |> put_flash(:info, "confirmado.") |> assign(order: reload(order))}
  end

  def handle_event("cancel", _params, socket) do
    {:ok, order} = Orders.cancel_order(socket.assigns.order.id)
    {:noreply, socket |> put_flash(:info, "cancelado.") |> assign(order: reload(order))}
  end

  defp reload(%{id: id}), do: Orders.get_order!(id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <a href={~p"/admin"} class="text-xs text-dim">← Painel</a>

        <header class="stack-2">
          <h1 class="text-xl text-mono">{@order.customer_name}</h1>
          <.status_badge status={@order.status} />
          <p class="text-xs text-dim text-mono">@{@order.customer_instagram}</p>
        </header>

        <ul class="stack-2">
          <li :for={item <- @order.items} class="row space-between text-sm">
            <span>{item.quantity}× {item.product_name_snapshot}</span>
            <span class="text-mono">
              {SeshLabWeb.CoreComponents.money(item.unit_price_cents * item.quantity)}
            </span>
          </li>
        </ul>

        <div class="row space-between total-line">
          <span class="text-sm text-muted">total</span>
          <span class="text-mono text-lg">
            {SeshLabWeb.CoreComponents.money(@order.total_cents)}
          </span>
        </div>

        <dl class="stack-1 text-sm">
          <div class="row space-between">
            <dt class="text-muted">entrega</dt>
            <dd>{@order.delivery_type}</dd>
          </div>
          <div :if={@order.address} class="stack-1">
            <dt class="text-muted">endereço</dt>
            <dd class="text-xs">{@order.address}</dd>
          </div>
          <div class="row space-between">
            <dt class="text-muted">pagamento</dt>
            <dd>{@order.payment_method}</dd>
          </div>
          <div :if={@order.notes} class="stack-1">
            <dt class="text-muted">observações</dt>
            <dd class="text-xs">{@order.notes}</dd>
          </div>
          <div class="row space-between">
            <dt class="text-muted">recebido</dt>
            <dd class="text-mono text-xs">
              {SeshLab.Clock.format(@order.inserted_at, :datetime)}
            </dd>
          </div>
        </dl>

        <div :if={@order.status == :pending} class="stack-2">
          <.button phx-click="confirm" class="btn--block">confirmar pagamento</.button>
          <.button phx-click="cancel" variant={:danger} class="btn--block">cancelar pedido</.button>
        </div>

        <section class="stack-2">
          <h2 class="text-sm text-muted">instagram</h2>
          <a
            href={Instagram.dm_url(@order.customer_instagram)}
            target="_blank"
            rel="noopener"
            class="btn btn--primary btn--block"
          >
            abrir dm
          </a>
          <a
            href={Instagram.profile_url(@order.customer_instagram)}
            target="_blank"
            rel="noopener"
            class="btn btn--ghost btn--block"
          >
            ver perfil
          </a>
        </section>
      </section>
    </Layouts.admin>
    """
  end
end
