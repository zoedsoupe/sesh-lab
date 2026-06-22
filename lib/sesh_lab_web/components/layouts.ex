defmodule SeshLabWeb.Layouts do
  @moduledoc false
  use SeshLabWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="shell">
      <header class="site-header">
        <a href={~p"/"} class="brand">
          <.sesh_logo />
        </a>
        <nav class="site-nav row gap-3 align-center">
          <a href={~p"/meus-ingressos"}>Ingressos</a>
          <a href={~p"/sobre"}>Sobre</a>
          <a href={~p"/avisos"}>Avisos</a>
        </nav>
      </header>

      <main class="site-main">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, default: %{}
  attr :back, :string, default: nil, doc: "back-link label; omit on root (/admin)"
  attr :back_to, :string, default: "/admin", doc: "back-link target"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="shell shell--admin">
      <header class="site-header">
        <a href={~p"/admin"} class="brand row gap-2 align-center">
          <.sesh_logo class="sesh-logo--sm" />
          <span class="text-mono text-xs text-dim">/admin</span>
        </a>
        <nav class="site-nav row gap-3">
          <a href={~p"/"}>Site</a>
        </nav>
      </header>

      <main class="site-main">
        <a :if={@back} href={@back_to} class="text-xs text-dim">← {@back}</a>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :kind, :atom, required: true
  attr :flash, :map, required: true
  attr :title, :string, default: nil

  def flash(assigns) do
    msg = Phoenix.Flash.get(assigns.flash, assigns.kind)
    assigns = assign(assigns, msg: msg, dom_id: assigns.id || "flash-#{assigns.kind}")

    ~H"""
    <div
      :if={@msg}
      id={@dom_id}
      class={"flash flash--#{@kind}"}
      role="alert"
      phx-hook="Flash"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind})}
      title="toque pra dispensar"
    >
      <p :if={@title} class="flash-title">{@title}</p>
      <p>{@msg}</p>
    </div>
    """
  end
end
