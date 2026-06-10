defmodule SeshLabWeb.ErrorHTMLTest do
  use SeshLabWeb.ConnCase, async: true

  alias SeshLabWeb.ErrorHTML

  defp render_str(template) do
    template
    |> ErrorHTML.render(%{__changed__: nil})
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  test "renders 404.html with custom page" do
    body = render_str("404.html")
    assert body =~ "404"
    assert body =~ "Página não encontrada."
    assert body =~ "Voltar à vitrine"
  end

  test "renders 401.html with custom page" do
    body = render_str("401.html")
    assert body =~ "401"
    assert body =~ "Acesso restrito."
  end

  test "renders 500.html with custom page" do
    body = render_str("500.html")
    assert body =~ "500"
    assert body =~ "Algo quebrou aqui."
  end

  test "unknown templates fall back to Phoenix status message" do
    assert ErrorHTML.render("418.html", %{}) == "I'm a teapot"
  end
end
