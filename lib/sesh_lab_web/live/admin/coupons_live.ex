defmodule SeshLabWeb.Admin.CouponsLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Coupons}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Cupons")
     |> assign(:rules, Coupons.list_rules())
     |> assign(:coupons, Coupons.list_public_coupons())}
  end

  defp discount(%{discount_kind: :percent, discount_value: v}), do: "#{v}%"

  defp discount(%{discount_kind: :fixed, discount_value: v}),
    do: SeshLabWeb.CoreComponents.money(v)

  defp expiry(nil), do: "Sem expirar"
  defp expiry(exp), do: "até #{Clock.format(exp, :date)}"

  defp uses(%{max_uses: nil, uses_count: n}), do: "#{n} usos"
  defp uses(%{max_uses: max, uses_count: n}), do: "#{n}/#{max} usos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <h1 class="text-xl text-mono">Cupons</h1>

        <section class="stack-3">
          <div class="row space-between align-baseline">
            <h2 class="text-sm text-muted">Regras automáticas</h2>
            <a href={~p"/admin/cupons/regras/nova"} class="text-xs text-accent">+ Nova regra</a>
          </div>
          <p class="text-xs text-dim">
            Emitem um cupom pro cliente quando o pedido atinge o valor mínimo.
          </p>

          <p :if={@rules == []} class="text-xs text-dim">Nenhuma regra ainda.</p>
          <ul class="stack-2">
            <li :for={r <- @rules} class="card">
              <a href={~p"/admin/cupons/regras/#{r.id}"} class="row space-between align-center">
                <div class="stack-1">
                  <span class="text-sm">{r.name}</span>
                  <span class="text-xs text-dim text-mono">
                    min {SeshLabWeb.CoreComponents.money(r.min_order_cents)} → {discount(r)} - {r.expires_in_days}d
                  </span>
                </div>
                <span :if={not r.is_active} class="badge badge--expired">Inativa</span>
              </a>
            </li>
          </ul>
        </section>

        <section class="stack-3">
          <div class="row space-between align-baseline">
            <h2 class="text-sm text-muted">Cupons públicos</h2>
            <a href={~p"/admin/cupons/novo"} class="text-xs text-accent">+ Novo cupom</a>
          </div>
          <p class="text-xs text-dim">
            Código que qualquer cliente usa. inscritos recebem aviso ao criar.
          </p>

          <p :if={@coupons == []} class="text-xs text-dim">Nenhum cupom público ainda.</p>
          <ul class="stack-2">
            <li :for={c <- @coupons} class="card">
              <a href={~p"/admin/cupons/#{c.id}"} class="row space-between align-center">
                <div class="stack-1">
                  <span class="text-sm text-mono">{c.code}</span>
                  <span class="text-xs text-dim">
                    {discount(c)} - {expiry(c.expires_at)} - {uses(c)}
                  </span>
                </div>
                <span :if={not c.is_active} class="badge badge--expired">Inativo</span>
              </a>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.admin>
    """
  end
end
