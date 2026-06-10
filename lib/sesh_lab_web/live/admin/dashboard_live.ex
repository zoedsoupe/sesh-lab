defmodule SeshLabWeb.Admin.DashboardLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Catalog, Orders, Promos, Settings}

  @topic "admin:orders"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SeshLab.PubSub, @topic)
      Phoenix.PubSub.subscribe(SeshLab.PubSub, Settings.topic())
    end

    {:ok, load_data(socket)}
  end

  @impl true
  def handle_info({:new_order, _id}, socket), do: {:noreply, load_data(socket)}
  def handle_info({:order_updated, _id}, socket), do: {:noreply, load_data(socket)}

  def handle_info({:high_demand_changed, value}, socket),
    do: {:noreply, assign(socket, high_demand: value)}

  @impl true
  def handle_event("toggle_high_demand", _params, socket) do
    {:ok, settings} = Settings.toggle_high_demand()
    {:noreply, assign(socket, high_demand: settings.is_high_demand)}
  end

  defp load_data(socket) do
    assign(socket,
      pending: Orders.list_pending(),
      recent: Orders.list_recent(20),
      products: Catalog.list_all_products(),
      promos: Promos.list_all(),
      high_demand: Settings.high_demand?()
    )
  end

  defp preorder?(order) do
    Enum.any?(order.items, & &1.lead_time_days_snapshot)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <div class="row space-between align-baseline">
          <h1 class="text-xl text-mono">Painel</h1>
          <button
            type="button"
            data-push-toggle
            class="text-xs text-muted underline-offset-2 hover:underline"
          >
            carregando…
          </button>
        </div>

        <div
          class={[
            "alert stack-2",
            if(@high_demand, do: "alert--warning", else: "")
          ]}
          role="status"
        >
          <div class="row space-between align-center">
            <div class="stack-1">
              <span class="text-sm text-mono">
                {if @high_demand, do: "alta demanda: ON", else: "alta demanda: off"}
              </span>
              <span class="text-xs text-dim">
                {if @high_demand,
                  do: "clientes veem aviso de tempo de confirmação variável.",
                  else: "ative quando a sesh estiver cheia."}
              </span>
            </div>
            <button
              type="button"
              phx-click="toggle_high_demand"
              class={["btn", if(@high_demand, do: "btn--danger", else: "btn--ghost")]}
            >
              {if @high_demand, do: "desligar", else: "ativar"}
            </button>
          </div>
        </div>

        <nav class="row gap-3 text-xs">
          <a href={~p"/admin/cupons"} class="text-accent">Gerenciar cupons</a>
        </nav>

        <section class="stack-3">
          <h2 class="text-sm text-muted">Pendentes ({length(@pending)})</h2>

          <p :if={@pending == []} class="text-xs text-dim">Nenhum pedido pendente.</p>

          <ul class="stack-2">
            <li :for={o <- @pending} class="card">
              <a href={~p"/admin/pedidos/#{o.id}"} class="stack-1 block">
                <div class="row space-between">
                  <span class="text-base">{o.customer_name}</span>
                  <span class="text-mono text-sm">
                    {SeshLabWeb.CoreComponents.money(o.total_cents)}
                  </span>
                </div>
                <div class="row gap-3 text-xs">
                  <span :if={o.promo_id} class="chip chip--cinnamon">Promo: {o.promo_id}</span>
                  <span :if={preorder?(o)} class="chip chip--encomenda">Encomenda</span>
                </div>
                <div class="row space-between text-xs text-dim">
                  <span>
                    {Enum.map_join(o.items, " · ", &"#{&1.quantity}× #{&1.product_name_snapshot}")}
                  </span>
                  <span>{SeshLab.Clock.format(o.inserted_at, :time)}</span>
                </div>
              </a>
            </li>
          </ul>
        </section>

        <section class="stack-3">
          <div class="row space-between align-baseline">
            <h2 class="text-sm text-muted">Promos</h2>
            <a href={~p"/admin/promos/novo"} class="text-xs text-accent">+ Nova Promo</a>
          </div>
          <p :if={@promos == []} class="text-xs text-dim">Nenhuma promo ainda.</p>
          <ul class="stack-2">
            <li :for={promo <- @promos} class="card">
              <a href={~p"/admin/promos/#{promo.id}"} class="row space-between align-center">
                <div class="stack-1">
                  <span class="text-base">{promo.name}</span>
                  <span class="text-xs text-dim">
                    {length(promo.items)} {if length(promo.items) == 1, do: "item", else: "itens"} · {SeshLabWeb.CoreComponents.money(
                      promo.total_cents
                    )}
                  </span>
                </div>
                <span :if={not promo.is_active} class="badge badge--expired">Inativa</span>
              </a>
            </li>
          </ul>
        </section>

        <section class="stack-3">
          <div class="row space-between align-baseline">
            <h2 class="text-sm text-muted">Produtos</h2>
            <a href={~p"/admin/produtos/novo"} class="text-xs text-accent">+ Novo Produto</a>
          </div>
          <ul class="stack-2">
            <li :for={p <- @products} class="card">
              <a href={~p"/admin/produtos/#{p.id}"} class="row space-between align-center">
                <div class="stack-1">
                  <span class="text-base">{p.name}</span>
                  <span class="text-xs text-dim">
                    {p.stock} em estoque · {SeshLabWeb.CoreComponents.money(p.unit_price_cents)}
                  </span>
                  <span
                    :if={p.is_preorder}
                    class="chip chip--encomenda"
                  >
                    encomenda{if p.lead_time_days, do: " #{p.lead_time_days}d", else: ""}
                  </span>
                </div>
                <span :if={not p.is_active} class="badge badge--expired">inativo</span>
              </a>
            </li>
          </ul>
        </section>

        <section :if={@recent != []} class="stack-3">
          <h2 class="text-sm text-muted">Histórico</h2>
          <ul class="stack-2">
            <li :for={o <- @recent} class="row space-between text-sm">
              <a href={~p"/admin/pedidos/#{o.id}"} class="row space-between flex-1">
                <span>{o.customer_name}</span>
                <.status_badge status={o.status} />
              </a>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.admin>
    """
  end
end
