defmodule SeshLabWeb.Admin.OrderShowLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Tickets}
  alias SeshLab.Tickets.Ticket
  alias SeshLab.Merch.Unit
  alias SeshLabWeb.Instagram

  @topic "admin:orders"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(SeshLab.PubSub, @topic)
    {:ok, assign(socket, order: Tickets.get_order!(id), page_title: "Pedido")}
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    case Tickets.confirm_order(socket.assigns.order.id) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Pagamento confirmado. #{length(order.tickets)} ingresso(s) emitido(s)."
         )
         |> assign(order: order)}

      {:error, :not_pending} ->
        {:noreply,
         socket
         |> put_flash(:error, "Pedido não está mais pendente (foi cancelado ou já confirmado).")
         |> reload()}

      {:error, {:sold_out, _id}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Ingressos esgotaram antes da confirmação. Pedido segue pendente.")
         |> reload()}

      {:error, {:merch_sold_out, _id}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Produto esgotou antes da confirmação. Pedido segue pendente.")
         |> reload()}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Não foi possível confirmar.") |> reload()}
    end
  end

  def handle_event("cancel", _params, socket) do
    case Tickets.cancel_order(socket.assigns.order.id) do
      {:ok, order} ->
        {:noreply, socket |> put_flash(:info, "Pedido cancelado.") |> assign(order: order)}

      {:error, :not_cancellable} ->
        {:noreply, socket |> put_flash(:error, "Esse pedido não pode ser cancelado.") |> reload()}
    end
  end

  @impl true
  def handle_info({event, id}, %{assigns: %{order: %{id: id}}} = socket)
      when event in [:order_updated, :new_order, :soldout] do
    {:noreply, reload(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload(socket), do: assign(socket, order: Tickets.get_order!(socket.assigns.order.id))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <header class="stack-2">
          <h1 class="text-xl text-mono">{@order.customer_name}</h1>
          <.status_badge status={@order.status} />
          <p class="text-xs text-dim text-mono">@{@order.customer_instagram}</p>
        </header>

        <ul class="stack-2">
          <li :for={item <- @order.items} class="row space-between text-sm">
            <span>{item.quantity}x {SeshLab.Tickets.OrderItem.line_name(item)}</span>
            <span class="text-mono">{money(item.unit_price_cents * item.quantity)}</span>
          </li>
        </ul>

        <div :if={@order.discount_cents > 0} class="row space-between text-sm text-accent">
          <span>Cupom {@order.coupon_code}</span>
          <span class="text-mono">- {money(@order.discount_cents)}</span>
        </div>

        <div class="row space-between total-line">
          <span class="text-sm text-muted">Total</span>
          <span class="text-mono text-lg">{money(@order.total_cents)}</span>
        </div>

        <dl class="stack-1 text-sm">
          <div class="row space-between">
            <dt class="text-muted">Recebido</dt>
            <dd class="text-mono text-xs">{Clock.format(@order.inserted_at, :datetime)}</dd>
          </div>
        </dl>

        <div :if={@order.status == :pending} class="stack-2">
          <.button phx-click="confirm" class="btn--block">Confirmar pagamento</.button>
          <.button
            phx-click="cancel"
            data-confirm="Cancelar e devolver capacidade?"
            variant={:danger}
            class="btn--block"
          >
            Cancelar pedido
          </.button>
        </div>

        <div :if={@order.status == :confirmed} class="stack-2">
          <.button
            phx-click="cancel"
            data-confirm="Cancelar pedido confirmado? Isso apaga os ingressos e produtos emitidos."
            variant={:danger}
            class="btn--block"
          >
            Cancelar pedido
          </.button>
        </div>

        <section :if={@order.tickets != []} class="stack-2">
          <h2 class="text-sm text-muted">Ingressos emitidos ({length(@order.tickets)})</h2>
          <ul class="stack-1">
            <li :for={t <- @order.tickets} class="row space-between text-sm">
              <span class="text-mono">{Ticket.display_code(t)}</span>
              <span :if={t.used_at} class="text-xs text-dim">
                Validado {Clock.format(t.used_at, :time)}
              </span>
              <span :if={is_nil(t.used_at)} class="text-xs text-dim">Não usado</span>
            </li>
          </ul>
        </section>

        <section :if={@order.merch_units != []} class="stack-2">
          <h2 class="text-sm text-muted">Produtos emitidos ({length(@order.merch_units)})</h2>
          <ul class="stack-1">
            <li :for={u <- @order.merch_units} class="row space-between text-sm">
              <span>
                <span class="text-mono">{Unit.display_code(u)}</span> · {u.merch_item_name_snapshot}
              </span>
              <span :if={u.redeemed_at} class="text-xs text-dim">
                Retirado {Clock.format(u.redeemed_at, :time)}
              </span>
              <span :if={is_nil(u.redeemed_at)} class="text-xs text-dim">Não retirado</span>
            </li>
          </ul>
        </section>

        <%!-- DM é o único canal admin↔cliente (aprovação de pagamento async no
              Instagram), tão importante quanto confirmar — fica em destaque. --%>
        <a
          href={Instagram.dm_url(@order.customer_instagram)}
          target="_blank"
          rel="noopener"
          class="btn btn--primary btn--block"
        >
          Abrir DM
        </a>

        <details class="stack-2">
          <summary class="text-sm text-muted">Link do pedido / perfil</summary>
          <div class="stack-2">
            <p id="order-link" class="text-mono text-xs break-all">{url(~p"/compra/#{@order.id}")}</p>
            <button type="button" data-copy-target="#order-link" class="btn btn--ghost btn--block">
              Copiar link
            </button>
            <a
              href={Instagram.profile_url(@order.customer_instagram)}
              target="_blank"
              rel="noopener"
              class="btn btn--ghost btn--block"
            >
              Ver perfil
            </a>
          </div>
        </details>
      </section>
    </Layouts.admin>
    """
  end
end
