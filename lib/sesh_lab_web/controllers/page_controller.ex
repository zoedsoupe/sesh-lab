defmodule SeshLabWeb.PageController do
  use SeshLabWeb, :controller

  alias SeshLab.Editions

  def index(conn, _params) do
    edition = Editions.current_edition()

    conn
    |> assign(:accent, edition && edition.accent_color)
    |> render(:index, edition: edition, page_title: edition && edition.name)
  end

  def sobre(conn, _params) do
    render(conn, :sobre, page_title: "Sobre")
  end

  # Notification config panel. Stateless shell — the toggle/topics reflect the
  # device's own subscription, managed client-side (assets/js/client_push.js).
  def avisos(conn, _params) do
    render(conn, :avisos, page_title: "Avisos")
  end
end
