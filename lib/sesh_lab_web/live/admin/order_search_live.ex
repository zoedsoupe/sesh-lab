defmodule SeshLabWeb.Admin.OrderSearchLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Tickets}

  # ponytail: load-more grows the limit and re-queries — no offset bookkeeping,
  # no keyset cursor. Re-fetching a growing recent-list is fine at admin scale;
  # switch to keyset if the orders table ever gets big.
  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       term: "",
       limit: @page_size,
       results: Tickets.list_recent(@page_size),
       page_title: "Pedidos"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => term}, socket) do
    if searching?(term) do
      {:noreply, assign(socket, term: term, results: Tickets.search_orders(term))}
    else
      # cleared/short term: back to history, reset paging
      {:noreply,
       assign(socket, term: term, limit: @page_size, results: Tickets.list_recent(@page_size))}
    end
  end

  def handle_event("load_more", _params, socket) do
    limit = socket.assigns.limit + @page_size
    {:noreply, assign(socket, limit: limit, results: Tickets.list_recent(limit))}
  end

  defp order_url(id), do: url(~p"/compra/#{id}")

  defp searching?(term), do: String.length(String.trim(term)) >= 2

  # More to load only while the history view fills the current limit exactly.
  defp more?(term, results, limit), do: not searching?(term) and length(results) >= limit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-4">
        <h1 class="text-xl text-mono">Pedidos</h1>

        <form phx-change="search">
          <input
            type="text"
            name="q"
            value={@term}
            phx-debounce="300"
            autocomplete="off"
            placeholder="@handle ou nome"
            class="input text-mono"
          />
        </form>

        <p class="text-xs text-dim">
          {if searching?(@term), do: "Resultados da busca.", else: "Pedidos mais recentes."}
        </p>

        <p :if={searching?(@term) and @results == []} class="text-sm text-dim">
          Nenhum pedido encontrado.
        </p>
        <p :if={not searching?(@term) and @results == []} class="text-sm text-dim">
          Nenhum pedido ainda.
        </p>

        <ul class="stack-2">
          <li :for={o <- @results} class="card stack-2">
            <a href={~p"/admin/pedidos/#{o.id}"} class="stack-1 block">
              <div class="row space-between">
                <span class="text-base text-accent text-cap">{o.customer_name}</span>
                <.status_badge status={o.status} />
              </div>
              <div class="row space-between text-xs text-dim">
                <span class="text-mono">@{o.customer_instagram}</span>
                <span class="text-mono">{money(o.total_cents)}</span>
              </div>
              <span class="text-xs text-dim text-mono">{Clock.format(o.inserted_at, :datetime)}</span>
            </a>
            <%!-- ponytail: inline onclick clipboard, not the data-copy-target hook —
                  LiveView-diffed rows aren't re-bound by copy.js (no page-loading-stop
                  on phx-change). UUID url has no quotes to escape. --%>
            <button
              type="button"
              onclick={"navigator.clipboard.writeText('#{order_url(o.id)}')"}
              class="btn btn--ghost btn--sm btn--block"
            >
              Copiar link
            </button>
          </li>
        </ul>

        <button
          :if={more?(@term, @results, @limit)}
          type="button"
          phx-click="load_more"
          class="btn btn--ghost btn--block"
        >
          Carregar mais
        </button>
      </section>
    </Layouts.admin>
    """
  end
end
