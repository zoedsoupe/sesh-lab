defmodule SeshLabWeb.Admin.BalcaoLive do
  @moduledoc """
  Balcão da festa, dois modos:

  - **Vender** (POS): grade de consumíveis (`Merch` kind `:counter`), carrinho,
    pago na hora em dinheiro ou PIX instantâneo (QR pro total → "Recebido").
    Registra via `Bar.record_sale/3`, baixa estoque dos itens rastreados.
  - **Resgatar**: scanner de QR de merch pré-pago (`Merch.redeem_unit/1`), cada
    código retira uma vez. Inalterado.
  """
  use SeshLabWeb, :live_view

  alias SeshLab.{Bar, Clock, Editions, Merch}
  alias SeshLab.Payments.Pix

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       mode: :sell,
       items: Merch.list_counter_items(),
       edition: Editions.current_edition(),
       cart: %{},
       pix: nil,
       sale: nil,
       result: nil,
       page_title: "Balcão"
     )}
  end

  # ── modo ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("set-mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: to_mode(mode), pix: nil, sale: nil, result: nil)}
  end

  # ── POS ─────────────────────────────────────────────────────────────────────

  def handle_event("add", %{"id" => id}, socket) do
    {:noreply, assign(socket, cart: bump(socket.assigns, id, +1), sale: nil, pix: nil)}
  end

  def handle_event("sub", %{"id" => id}, socket) do
    {:noreply, assign(socket, cart: bump(socket.assigns, id, -1), pix: nil)}
  end

  def handle_event("clear-cart", _params, socket) do
    {:noreply, assign(socket, cart: %{}, pix: nil)}
  end

  def handle_event("pay-cash", _params, socket), do: {:noreply, checkout(socket, :cash)}

  def handle_event("pay-pix", _params, socket) do
    total = cart_total(socket.assigns)

    if total > 0 do
      {:noreply, assign(socket, pix: pix_for(total))}
    else
      {:noreply, put_flash(socket, :error, "Carrinho vazio.")}
    end
  end

  def handle_event("confirm-pix", _params, socket), do: {:noreply, checkout(socket, :pix)}

  def handle_event("cancel-pix", _params, socket), do: {:noreply, assign(socket, pix: nil)}

  def handle_event("dismiss-sale", _params, socket), do: {:noreply, assign(socket, sale: nil)}

  # ── Resgate (scanner) ───────────────────────────────────────────────────────

  def handle_event("manual", %{"code" => code}, socket), do: {:noreply, redeem(socket, code)}

  def handle_event("scan", %{"code" => code}, socket), do: {:noreply, redeem(socket, code)}

  def handle_event("clear", _params, socket), do: {:noreply, assign(socket, result: nil)}

  def handle_event("camera_error", %{"name" => name}, socket) do
    msg =
      case name do
        "NotAllowedError" -> "Câmera negada. Use o código manual abaixo."
        "NotFoundError" -> "Nenhuma câmera encontrada. Use o código manual."
        _ -> "Não foi possível abrir a câmera. Use o código manual."
      end

    {:noreply, put_flash(socket, :error, msg)}
  end

  # ── core ────────────────────────────────────────────────────────────────────

  defp checkout(socket, method) do
    edition_id = socket.assigns.edition && socket.assigns.edition.id

    case Bar.record_sale(edition_id, method, socket.assigns.cart) do
      {:ok, sale} ->
        socket
        |> assign(cart: %{}, pix: nil, sale: %{total: sale.total_cents, method: method})
        |> assign(items: Merch.list_counter_items())

      {:error, :empty_cart} ->
        put_flash(socket, :error, "Carrinho vazio.")

      {:error, {:sold_out, name}} when is_binary(name) ->
        socket
        |> assign(pix: nil, items: Merch.list_counter_items())
        |> put_flash(:error, "#{name} esgotou.")

      {:error, _} ->
        socket |> assign(pix: nil) |> put_flash(:error, "Não foi possível registrar a venda.")
    end
  end

  defp bump(assigns, id, delta) do
    qty = Map.get(assigns.cart, id, 0) + delta
    cap = available_for(assigns.items, id)

    cond do
      qty <= 0 -> Map.delete(assigns.cart, id)
      cap && qty > cap -> Map.put(assigns.cart, id, cap)
      true -> Map.put(assigns.cart, id, qty)
    end
  end

  # nil = estoque não rastreado (sem teto).
  defp available_for(items, id) do
    case Enum.find(items, &(&1.id == id)) do
      %{track_stock: true, available: avail} -> avail
      _ -> nil
    end
  end

  defp cart_total(assigns) do
    Enum.sum_by(assigns.cart, fn {id, qty} -> qty * price_of(assigns.items, id) end)
  end

  defp price_of(items, id) do
    case Enum.find(items, &(&1.id == id)) do
      %{price_cents: c} -> c
      _ -> 0
    end
  end

  defp pix_for(total_cents) do
    cfg = Application.fetch_env!(:sesh_lab, :pix)

    emv =
      Pix.build(
        pix_key: cfg[:key],
        amount_cents: total_cents,
        merchant_name: cfg[:merchant_name],
        merchant_city: cfg[:merchant_city],
        txid: "BALCAO"
      )

    %{emv: emv, svg: Pix.to_svg(emv), total: total_cents}
  end

  defp redeem(socket, code) do
    result =
      case Merch.redeem_unit(code) do
        {:ok, unit} -> %{kind: :ok, item: unit.merch_item_name_snapshot, at: unit.redeemed_at}
        {:error, {:already_redeemed, at}} -> %{kind: :already_redeemed, at: at}
        {:error, :not_found} -> %{kind: :not_found}
      end

    assign(socket, result: result)
  end

  defp to_mode("redeem"), do: :redeem
  defp to_mode(_), do: :sell

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-4">
        <header class="stack-1">
          <h1 class="text-xl text-mono">Balcão</h1>
          <p :if={@edition} class="text-xs text-dim">{@edition.name}</p>
        </header>

        <div class="tabs" role="tablist">
          <button
            type="button"
            class={["tab", @mode == :sell && "tab--active"]}
            phx-click="set-mode"
            phx-value-mode="sell"
          >
            Vender
          </button>
          <button
            type="button"
            class={["tab", @mode == :redeem && "tab--active"]}
            phx-click="set-mode"
            phx-value-mode="redeem"
          >
            Resgatar
          </button>
        </div>

        <.pos :if={@mode == :sell} items={@items} cart={@cart} total={cart_total(assigns)} />
        <.scanner :if={@mode == :redeem} />
      </section>

      <%!-- PIX: QR pro total, confirma ao receber --%>
      <div :if={@pix} class="sheet" role="dialog">
        <div class="sheet-body stack-3">
          <p class="text-sm text-dim">PIX · {money(@pix.total)}</p>
          <div class="qr-frame" aria-label="qr code pix">{Phoenix.HTML.raw(@pix.svg)}</div>
          <code class="pix-copy text-mono text-xs" id="balcao-pix-copy" data-pix-copy>
            {@pix.emv}
          </code>
          <button type="button" class="btn btn--ghost btn--block" data-copy-target="#balcao-pix-copy">
            copiar código
          </button>
          <.button type="button" variant={:primary} class="btn--block" phx-click="confirm-pix">
            Recebido
          </.button>
          <button type="button" class="text-xs text-dim" phx-click="cancel-pix">cancelar</button>
        </div>
      </div>

      <%!-- confirmação da venda --%>
      <div :if={@sale} class="scan-result scan-result--ok" phx-click="dismiss-sale" role="status">
        <div class="scan-result-inner stack-2">
          <span class="scan-result-mark">✓</span>
          <span class="text-xl text-mono">{money(@sale.total)}</span>
          <span class="text-sm text-dim">{payment_label(@sale.method)}</span>
          <span class="text-xs text-dim">Toque pra continuar</span>
        </div>
      </div>

      <%!-- resultado do resgate (scanner) --%>
      <div
        :if={@result}
        class={["scan-result", scan_result_class(@result.kind)]}
        phx-click="clear"
        role="status"
      >
        <div class="scan-result-inner stack-2">
          <%= case @result.kind do %>
            <% :ok -> %>
              <span class="scan-result-mark">✓</span>
              <span class="text-xl text-mono">{@result.item}</span>
              <span class="text-sm text-dim">Retirado {Clock.format(@result.at, :time)}</span>
            <% :already_redeemed -> %>
              <span class="scan-result-mark">✕</span>
              <span class="text-xl text-mono">Já retirado</span>
              <span class="text-sm">Às {Clock.format(@result.at, :time)}</span>
            <% :not_found -> %>
              <span class="scan-result-mark">✕</span>
              <span class="text-xl text-mono">Não encontrado</span>
          <% end %>
          <span class="text-xs text-dim">Toque pra continuar</span>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  # ── POS subcomponent ─────────────────────────────────────────────────────────

  attr :items, :list, required: true
  attr :cart, :map, required: true
  attr :total, :integer, required: true

  defp pos(assigns) do
    ~H"""
    <div class="stack-3">
      <div :if={@items == []} class="text-sm text-dim">
        Nenhum item de balcão. Cadastre em
        <.link navigate={~p"/admin/produtos/novo"} class="text-accent">Produtos</.link>
        com tipo “balcão”.
      </div>

      <ul :if={@items != []} class="pos-grid">
        <li :for={item <- @items} class="pos-item">
          <button type="button" class="pos-item-tap" phx-click="add" phx-value-id={item.id}>
            <span class="pos-item-name">{item.name}</span>
            <span class="pos-item-price text-mono text-xs text-dim">{money(item.price_cents)}</span>
            <span :if={item.track_stock} class="pos-item-stock text-xs text-dim">
              {item.available} no estoque
            </span>
          </button>
          <div :if={Map.get(@cart, item.id, 0) > 0} class="pos-item-qty">
            <button
              type="button"
              class="stepper-btn"
              phx-click="sub"
              phx-value-id={item.id}
              aria-label="tirar"
            >
              −
            </button>
            <span class="text-mono">{Map.get(@cart, item.id)}</span>
            <button
              type="button"
              class="stepper-btn"
              phx-click="add"
              phx-value-id={item.id}
              aria-label="por"
            >
              +
            </button>
          </div>
        </li>
      </ul>

      <div :if={@total > 0} class="pos-bar store-finish-bar stack-2">
        <div class="row space-between align-center">
          <span class="text-sm text-dim">Total</span>
          <span class="text-lg text-mono">{money(@total)}</span>
        </div>
        <div class="row gap-2">
          <.button type="button" variant={:ghost} class="flex-1" phx-click="pay-cash">
            Dinheiro
          </.button>
          <.button type="button" variant={:primary} class="flex-1" phx-click="pay-pix">PIX</.button>
        </div>
        <button type="button" class="text-xs text-dim" phx-click="clear-cart">limpar</button>
      </div>
    </div>
    """
  end

  defp scanner(assigns) do
    ~H"""
    <div id="scanner" phx-hook="Scanner" data-scanner class="scanner stack-4">
      <p class="text-xs text-dim">
        Escaneie o QR do produto pra retirar. Cada código retira uma vez.
      </p>

      <div id="cam-wrap" phx-update="ignore" class="scanner-cam">
        <video data-scanner-video playsinline autoplay muted class="scanner-video"></video>
      </div>

      <button type="button" data-scanner-activate class="btn btn--primary btn--block">
        Ativar câmera
      </button>

      <form phx-submit="manual" class="stack-2">
        <label class="field stack-1">
          <span class="field-label text-xs text-muted">Código manual</span>
          <input
            type="text"
            name="code"
            autocomplete="off"
            autocapitalize="characters"
            placeholder="XXXX-XXXX"
            class="field-input text-mono"
          />
        </label>
        <.button type="submit" variant={:ghost} class="btn--block">Resgatar código</.button>
      </form>
    </div>
    """
  end

  defp payment_label(:cash), do: "Dinheiro"
  defp payment_label(:pix), do: "PIX"

  defp scan_result_class(:ok), do: "scan-result--ok"
  defp scan_result_class(_), do: "scan-result--err"
end
