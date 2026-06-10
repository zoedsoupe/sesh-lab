defmodule SeshLabWeb.PageController do
  use SeshLabWeb, :controller

  alias SeshLab.{Catalog, Promos}

  @keepalive_ms 25_000

  def index(conn, _params) do
    {pronta, encomenda} = Catalog.list_active_partitioned()
    promos = Promos.list_active()

    render(conn, :index,
      pronta: pronta,
      encomenda: encomenda,
      promos: promos
    )
  end

  # Notification config panel. Stateless shell — the toggle/topics reflect the
  # device's own subscription, managed client-side (assets/js/client_push.js).
  def avisos(conn, _params) do
    render(conn, :avisos, page_title: "avisos")
  end

  # SSE stream of product stock changes. Replaces the meta-refresh on the
  # vitrine: client patches individual cards instead of reloading the page.
  def stock_stream(conn, _params) do
    Phoenix.PubSub.subscribe(SeshLab.PubSub, Catalog.stock_topic())

    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
    |> stream_loop()
  end

  defp stream_loop(conn) do
    receive do
      {:stock_changed, id, stock} ->
        payload = Jason.encode!(%{id: id, stock: stock})

        case Plug.Conn.chunk(conn, "data: " <> payload <> "\n\n") do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end
    after
      @keepalive_ms ->
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end
    end
  end
end
