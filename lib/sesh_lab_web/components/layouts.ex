defmodule SeshLabWeb.Layouts do
  @moduledoc false
  use SeshLabWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="shell">
      <header class="site-header">
        <a href={~p"/"} class="brand">
          <span class="brand-name text-mono text-sm">a.sesh.sesh</span>
        </a>
        <img src={~p"/images/mascara-72.png"} alt="" class="brand-logo" width="28" height="28" />
        <nav class="site-nav row gap-3 align-center">
          <a href={~p"/meus-pedidos"} class="text-dim text-xs">meus pedidos</a>
          <a href={~p"/avisos"} class="text-dim text-xs">avisos</a>
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
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="shell shell--admin">
      <header class="site-header">
        <a href={~p"/admin"} class="brand text-mono text-sm">/admin - a.sesh.sesh</a>
        <img src={~p"/images/mascara-72.png"} alt="" class="brand-logo" width="28" height="28" />
        <nav class="site-nav row gap-3">
          <a href={~p"/"} class="text-dim text-xs">vitrine</a>
        </nav>
      </header>

      <main class="site-main">
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
    assigns = assign(assigns, :msg, msg)

    ~H"""
    <div :if={@msg} id={@id} class={"flash flash--#{@kind}"} role="alert">
      <p :if={@title} class="flash-title">{@title}</p>
      <p>{@msg}</p>
    </div>
    """
  end
end
