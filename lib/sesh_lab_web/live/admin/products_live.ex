defmodule SeshLabWeb.Admin.ProductsLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Merch

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, items: Merch.list_items(), page_title: "Produtos")}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    item = Merch.get_item!(id)
    {:ok, _} = Merch.toggle_active(item)
    {:noreply, assign(socket, items: Merch.list_items())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <div class="row space-between align-baseline">
          <h1 class="text-xl text-mono">Produtos</h1>
          <a href={~p"/admin/produtos/novo"} class="admin-action admin-action--primary">+ Novo</a>
        </div>

        <p :if={@items == []} class="text-sm text-dim">Nenhum produto ainda.</p>

        <ul class="stack-2">
          <li :for={item <- @items} class="card stack-2">
            <a href={~p"/admin/produtos/#{item.id}"} class="row space-between align-baseline">
              <span class="text-base text-accent">{item.name}</span>
              <span class="text-mono text-sm">{money(item.price_cents)}</span>
            </a>
            <div class="row space-between text-xs text-dim">
              <span class="text-mono">disp {item.available} / {item.stock}</span>
              <span class="chip">{if item.is_active, do: "ativo", else: "inativo"}</span>
            </div>
            <button
              type="button"
              phx-click="toggle"
              phx-value-id={item.id}
              class="btn btn--ghost btn--sm btn--block"
            >
              {if item.is_active, do: "Desativar", else: "Ativar"}
            </button>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
