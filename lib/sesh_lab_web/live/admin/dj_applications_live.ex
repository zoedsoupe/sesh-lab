defmodule SeshLabWeb.Admin.DjApplicationsLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, DjApplications}
  alias SeshLabWeb.Instagram

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       applications: DjApplications.list(),
       open?: SeshLab.Settings.dj_applications_open?(),
       page_title: "Quer tocar"
     )}
  end

  @impl true
  def handle_event("toggle_open", _params, socket) do
    next = not socket.assigns.open?
    {:ok, _} = SeshLab.Settings.set_dj_applications_open(next)
    {:noreply, assign(socket, open?: next)}
  end

  # Brazilian numbers come in as DDD + número (10–11 dígitos); prepend country
  # code for the wa.me deep-link unless it's already there.
  defp wa_url(digits) when is_binary(digits) do
    full = if String.length(digits) <= 11, do: "55" <> digits, else: digits
    "https://wa.me/" <> full
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <header class="stack-1">
          <h1 class="text-xl text-mono">Quer tocar?</h1>
          <p class="text-xs text-dim">{length(@applications)} inscrição(ões)</p>
          <div class="row space-between align-baseline">
            <p class="text-xs text-dim">
              Inscrições: {if @open?, do: "abertas", else: "fechadas"}
            </p>
            <button type="button" phx-click="toggle_open" class="btn btn--ghost btn--sm">
              {if @open?, do: "Fechar", else: "Abrir"}
            </button>
          </div>
        </header>

        <p :if={@applications == []} class="text-sm text-dim">Nenhuma inscrição ainda.</p>

        <ul class="stack-3">
          <li :for={a <- @applications} class="card stack-2">
            <div class="row space-between align-baseline">
              <h2 class="text-base">{a.name}</h2>
              <span class="text-xs text-dim text-mono">{Clock.format(a.inserted_at, :date)}</span>
            </div>

            <p class="text-sm">{a.musical_styles}</p>
            <p class="text-sm text-dim">{a.about}</p>

            <div class="row gap-3 text-xs">
              <a href={wa_url(a.whatsapp)} target="_blank" rel="noopener" class="text-accent">
                Whatsapp
              </a>
              <a
                href={Instagram.profile_url(a.instagram)}
                target="_blank"
                rel="noopener"
                class="text-accent"
              >
                @{a.instagram}
              </a>
            </div>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
