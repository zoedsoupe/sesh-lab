defmodule SeshLabWeb.Admin.OrderSearchLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Tickets

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, results: [], term: "", page_title: "Buscar")}
  end

  @impl true
  def handle_event("search", %{"q" => term}, socket) do
    {:noreply, assign(socket, term: term, results: Tickets.search_orders(term))}
  end

  defp order_url(id), do: url(~p"/compra/#{id}")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-4">
        <h1 class="text-xl text-mono">Buscar pedido</h1>

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

        <p :if={@term != "" and @results == []} class="text-sm text-dim">
          Nenhum pedido encontrado.
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
      </section>
    </Layouts.admin>
    """
  end
end
