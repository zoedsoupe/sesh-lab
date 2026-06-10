defmodule SeshLabWeb.ErrorHTML do
  @moduledoc """
  Páginas de erro minimalistas (404, 401, 500). Sem layout — auto-contidas
  para evitar dependência da camada que pode estar quebrada quando o erro
  acontece.
  """

  use SeshLabWeb, :html

  def render("404.html", assigns), do: page("404", "Página não encontrada.", assigns)
  def render("401.html", assigns), do: page("401", "Acesso restrito.", assigns)

  def render("500.html", assigns),
    do: page("500", "Algo quebrou aqui. já estamos vendo.", assigns)

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)

  defp page(code, message, assigns) do
    assigns = assign(assigns, code: code, message: message)

    ~H"""
    <!DOCTYPE html>
    <html lang="pt-br">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex,nofollow" />
        <meta name="theme-color" content="#0a0a0a" />
        <title>{@code} - a.sesh.sesh</title>
        <link rel="icon" href="/images/mascara-192.png" type="image/png" />
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      <body class="bg-base text-fg text-sans">
        <main class="shell error-page">
          <img src="/images/mascara-192.png" alt="" class="error-logo" width="96" height="96" />
          <p class="text-mono text-2xl text-accent">{@code}</p>
          <p class="text-base text-muted">{@message}</p>
          <a href="/" class="btn btn--ghost btn--block">Voltar à vitrine</a>
          <p class="text-xs text-dim text-mono">— Pandora</p>
        </main>
      </body>
    </html>
    """
  end
end
