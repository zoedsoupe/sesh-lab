defmodule SeshLabWeb.Admin.DashboardLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Editions, Tickets}
  alias SeshLab.Editions.Edition

  @topic "admin:orders"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(SeshLab.PubSub, @topic)

    editions = Editions.list_editions()
    {:ok, socket |> assign(editions: editions) |> select_edition(default_edition(editions))}
  end

  @impl true
  def handle_event("select_edition", %{"id" => id}, socket) do
    edition = Enum.find(socket.assigns.editions, &(&1.id == id))
    {:noreply, select_edition(socket, edition)}
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:new_order, :order_updated, :soldout] do
    {:noreply, refresh(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── data ────────────────────────────────────────────────────────────────────

  defp default_edition([]), do: nil

  defp default_edition(editions) do
    Enum.find(editions, &(&1.status == :published)) || List.first(editions)
  end

  defp select_edition(socket, nil) do
    assign(socket,
      edition: nil,
      stats: nil,
      by_type: %{},
      pending: [],
      recent: [],
      page_title: "painel"
    )
  end

  defp select_edition(socket, %Edition{} = edition) do
    socket
    |> assign(edition: edition, page_title: "painel — #{edition.name}")
    |> refresh()
  end

  defp refresh(%{assigns: %{edition: nil}} = socket), do: socket

  defp refresh(%{assigns: %{edition: edition}} = socket) do
    # Reload editions so a publish/status change elsewhere reflects in the selector.
    editions = Editions.list_editions()
    edition = Enum.find(editions, &(&1.id == edition.id)) || edition

    assign(socket,
      editions: editions,
      edition: edition,
      stats: Tickets.stats(edition.id),
      by_type: Tickets.stats_by_type(edition.id),
      pending: edition_orders(Tickets.list_pending(), edition.id),
      recent: edition_orders(Tickets.list_recent(20), edition.id)
    )
  end

  defp edition_orders(orders, edition_id), do: Enum.filter(orders, &(&1.edition_id == edition_id))

  defp lote_stats(by_type, type) do
    s = Map.get(by_type, type.id, %{held: 0, sold: 0, validated: 0})
    Map.merge(s, %{capacity: type.capacity, available: type.available})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <div class="row space-between align-baseline">
          <h1 class="text-xl text-mono">painel</h1>
          <button
            type="button"
            data-push-toggle
            class="text-xs text-muted underline-offset-2 hover:underline"
          >
            carregando…
          </button>
        </div>

        <nav class="admin-actions">
          <a href={~p"/admin/edicoes/nova"} class="admin-action admin-action--primary">
            + nova edição
          </a>
          <a href={~p"/admin/validar"} class="admin-action">porta</a>
          <a href={~p"/admin/cupons"} class="admin-action">cupons</a>
          <a href={~p"/admin/tocar"} class="admin-action">quer tocar</a>
        </nav>

        <p :if={@editions == []} class="text-sm text-dim">
          nenhuma edição ainda.
          <a href={~p"/admin/edicoes/nova"} class="text-accent">criar a primeira →</a>
        </p>

        <section :if={@editions != []} class="stack-2">
          <label class="field-label text-xs text-muted">edição</label>
          <ul class="row gap-3 wrap">
            <li :for={e <- @editions}>
              <button
                type="button"
                phx-click="select_edition"
                phx-value-id={e.id}
                class={["chip", @edition && e.id == @edition.id && "chip--active"]}
              >
                {e.name} · {e.status}
              </button>
            </li>
          </ul>
        </section>

        <%= if @edition do %>
          <div class="stack-5" style={"--accent: #{@edition.accent_color}"}>
            <section class="stack-3">
              <div class="row space-between align-baseline">
                <h2 class="text-sm text-muted">{@edition.name}</h2>
                <a href={~p"/admin/edicoes/#{@edition.id}"} class="text-xs text-accent">Editar →</a>
              </div>

              <div class="stats-grid">
                <.stat label="capacidade" value={@stats.capacity} />
                <.stat label="vendido" value={@stats.sold_confirmed} />
                <.stat label="pendente" value={@stats.held_pending} />
                <.stat label="disponível" value={@stats.available} />
                <.stat label="validados" value={@stats.validated} />
              </div>
            </section>

            <section :if={@edition.ticket_types != []} class="stack-2">
              <h2 class="text-sm text-muted">lotes</h2>
              <table class="stats-table text-sm">
                <thead>
                  <tr class="text-xs text-dim">
                    <th class="text-left">lote</th>
                    <th>cap</th>
                    <th>vend</th>
                    <th>pend</th>
                    <th>disp</th>
                    <th>valid</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={type <- @edition.ticket_types}>
                    <% s = lote_stats(@by_type, type) %>
                    <td class="text-left">{type.name}</td>
                    <td class="text-mono">{s.capacity}</td>
                    <td class="text-mono">{s.sold}</td>
                    <td class="text-mono">{s.held}</td>
                    <td class="text-mono">{s.available}</td>
                    <td class="text-mono">{s.validated}</td>
                  </tr>
                </tbody>
              </table>
            </section>

            <section class="stack-3">
              <h2 class="text-sm text-muted">pendentes ({length(@pending)})</h2>
              <p :if={@pending == []} class="text-xs text-dim">nenhum pedido pendente.</p>
              <ul class="stack-2">
                <li :for={o <- @pending} class="card">
                  <a href={~p"/admin/pedidos/#{o.id}"} class="stack-1 block">
                    <div class="row space-between">
                      <span class="text-base text-accent text-cap">{o.customer_name}</span>
                      <span class="text-mono text-sm">{money(o.total_cents)}</span>
                    </div>
                    <div class="row space-between text-xs text-dim">
                      <span>
                        {Enum.map_join(
                          o.items,
                          " · ",
                          &"#{&1.quantity}× #{&1.ticket_type_name_snapshot}"
                        )}
                      </span>
                      <span>{Clock.format(o.inserted_at, :time)}</span>
                    </div>
                  </a>
                </li>
              </ul>
            </section>

            <section :if={@recent != []} class="stack-3">
              <h2 class="text-sm text-muted">histórico</h2>
              <ul class="stack-2">
                <li :for={o <- @recent} class="row space-between text-sm">
                  <a href={~p"/admin/pedidos/#{o.id}"} class="row space-between flex-1">
                    <span class="text-accent text-cap">{o.customer_name}</span>
                    <.status_badge status={o.status} />
                  </a>
                </li>
              </ul>
            </section>
          </div>
        <% end %>
      </section>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat(assigns) do
    ~H"""
    <div class="stat stack-1">
      <span class="text-mono text-lg">{@value}</span>
      <span class="text-xs text-dim">{@label}</span>
    </div>
    """
  end
end
