defmodule SeshLabWeb.SeoController do
  @moduledoc """
  robots.txt e sitemap.xml gerados dinamicamente, interpolando o host do
  Endpoint (que varia por ambiente). Sao rotas, nao arquivos estaticos, por
  isso `robots.txt`/`sitemap.xml` nao constam em `static_paths/0`.
  """
  use SeshLabWeb, :controller

  def robots(conn, _params) do
    host = SeshLabWeb.Endpoint.url()

    body = """
    User-agent: *
    Allow: /
    Disallow: /admin
    Disallow: /compra
    Disallow: /meus-ingressos
    Sitemap: #{host}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    host = SeshLabWeb.Endpoint.url()

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>#{host}/</loc></url>
      <url><loc>#{host}/loja</loc></url>
      <url><loc>#{host}/sobre</loc></url>
      <url><loc>#{host}/tocar</loc></url>
    </urlset>
    """

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, body)
  end
end
