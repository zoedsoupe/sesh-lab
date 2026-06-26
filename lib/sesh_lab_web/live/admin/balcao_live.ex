defmodule SeshLabWeb.Admin.BalcaoLive do
  @moduledoc """
  Resgate de merch no balcao. LiveView + hook de camera (`assets/js/scanner.js`):
  o cliente le o QR e da `pushEvent("scan", %{code})`; o servidor resgata
  atomicamente via `Merch.redeem_unit/1` e devolve painel verde/vermelho.

  Separado da porta: nao valida ingresso, retira uma unidade de merch uma unica
  vez.
  """
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Merch}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, result: nil, page_title: "Balcão")}
  end

  @impl true
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

  defp redeem(socket, code) do
    result =
      case Merch.redeem_unit(code) do
        {:ok, unit} -> %{kind: :ok, item: unit.merch_item_name_snapshot, at: unit.redeemed_at}
        {:error, {:already_redeemed, at}} -> %{kind: :already_redeemed, at: at}
        {:error, :not_found} -> %{kind: :not_found}
      end

    assign(socket, result: result)
  end

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section id="scanner" phx-hook="Scanner" data-scanner class="scanner stack-4">
        <header class="stack-1">
          <h1 class="text-xl text-mono">Balcão</h1>
          <p class="text-xs text-dim">
            Escaneie o QR do produto pra retirar. Cada código retira uma vez.
          </p>
        </header>

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

        <%!-- painel de resultado fullscreen --%>
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
      </section>
    </Layouts.admin>
    """
  end

  defp scan_result_class(:ok), do: "scan-result--ok"
  defp scan_result_class(_), do: "scan-result--err"
end
