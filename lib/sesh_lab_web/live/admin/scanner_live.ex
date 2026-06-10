defmodule SeshLabWeb.Admin.ScannerLive do
  @moduledoc """
  Validação na porta. LiveView + hook de câmera (`assets/js/scanner.js`):
  o cliente lê o QR e dá `pushEvent("scan", %{code})`; o servidor valida
  atomicamente via `Tickets.validate_ticket/1` e devolve painel verde/vermelho.

  Cada validação faz broadcast em `"door:<edition_id>"`, então vários celulares
  na porta veem o contador `validadas / vendidas` em tempo real.
  """
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Editions, Tickets}

  @impl true
  def mount(_params, _session, socket) do
    edition = Editions.current_edition()

    if connected?(socket) and edition do
      Phoenix.PubSub.subscribe(SeshLab.PubSub, "door:#{edition.id}")
    end

    {:ok,
     socket
     |> assign(
       scanner: true,
       edition: edition,
       result: nil,
       page_title: "porta"
     )
     |> load_stats()}
  end

  @impl true
  def handle_event("scan", %{"code" => code}, socket), do: {:noreply, validate(socket, code)}

  def handle_event("manual", %{"code" => code}, socket), do: {:noreply, validate(socket, code)}

  def handle_event("clear", _params, socket), do: {:noreply, assign(socket, result: nil)}

  def handle_event("camera_error", %{"name" => name}, socket) do
    msg =
      case name do
        "NotAllowedError" -> "câmera negada. use o código manual abaixo."
        "NotFoundError" -> "nenhuma câmera encontrada. use o código manual."
        _ -> "não foi possível abrir a câmera. use o código manual."
      end

    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:validated, _edition_id}, socket), do: {:noreply, load_stats(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── core ────────────────────────────────────────────────────────────────────

  defp validate(%{assigns: %{edition: nil}} = socket, _code), do: socket

  defp validate(socket, code) do
    result =
      case Tickets.validate_ticket(code) do
        {:ok, ticket} ->
          %{kind: :ok, lote: lote_name(ticket), name: buyer_name(ticket), at: ticket.used_at}

        {:error, {:already_used, at}} ->
          %{kind: :already_used, at: at}

        {:error, :not_found} ->
          %{kind: :not_found}
      end

    socket |> assign(result: result) |> load_stats()
  end

  defp lote_name(ticket) do
    case Editions.get_ticket_type!(ticket.ticket_type_id) do
      %{name: name} -> name
    end
  rescue
    Ecto.NoResultsError -> "ingresso"
  end

  defp buyer_name(%{order: %{customer_name: name}}), do: name
  defp buyer_name(_), do: ""

  defp load_stats(%{assigns: %{edition: nil}} = socket), do: assign(socket, stats: nil)

  defp load_stats(%{assigns: %{edition: edition}} = socket),
    do: assign(socket, stats: Tickets.stats(edition.id))

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section id="scanner" phx-hook="Scanner" data-scanner class="scanner stack-4">
        <div class="row space-between align-baseline">
          <a href={~p"/admin"} class="text-xs text-dim">← painel</a>
          <span :if={@stats} class="text-mono text-sm">
            validadas {@stats.validated} / vendidas {@stats.sold_confirmed}
          </span>
        </div>

        <p :if={is_nil(@edition)} class="text-sm text-dim">
          nenhuma edição publicada. publique uma edição pra abrir a porta.
        </p>

        <%= if @edition do %>
          <header class="stack-1">
            <h1 class="text-xl text-mono">porta — {@edition.name}</h1>
          </header>

          <div id="cam-wrap" phx-update="ignore" class="scanner-cam">
            <video data-scanner-video playsinline autoplay muted class="scanner-video"></video>
          </div>

          <button type="button" data-scanner-activate class="btn btn--primary btn--block">
            ativar câmera
          </button>

          <form phx-submit="manual" class="stack-2">
            <label class="field stack-1">
              <span class="field-label text-xs text-muted">código manual</span>
              <input
                type="text"
                name="code"
                autocomplete="off"
                autocapitalize="characters"
                placeholder="XXXX-XXXX"
                class="field-input text-mono"
              />
            </label>
            <.button type="submit" variant={:ghost} class="btn--block">validar código</.button>
          </form>
        <% end %>

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
                <span class="text-xl text-mono">{@result.lote}</span>
                <span :if={@result.name != ""} class="text-base">{@result.name}</span>
                <span class="text-sm text-dim">entrou {Clock.format(@result.at, :time)}</span>
              <% :already_used -> %>
                <span class="scan-result-mark">✕</span>
                <span class="text-xl text-mono">já validado</span>
                <span class="text-sm">às {Clock.format(@result.at, :time)}</span>
              <% :not_found -> %>
                <span class="scan-result-mark">✕</span>
                <span class="text-xl text-mono">não encontrado</span>
            <% end %>
            <span class="text-xs text-dim">toque pra continuar</span>
          </div>
        </div>
      </section>
    </Layouts.admin>
    """
  end

  defp scan_result_class(:ok), do: "scan-result--ok"
  defp scan_result_class(_), do: "scan-result--err"
end
