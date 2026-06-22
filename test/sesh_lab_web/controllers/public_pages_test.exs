defmodule SeshLabWeb.PublicPagesTest do
  use SeshLabWeb.ConnCase, async: false

  import SeshLab.Fixtures

  describe "without a published edition" do
    test "landing renders the teaser", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "SESH LAB."
      assert html =~ "em breve"
    end

    test "/comprar redirects when nothing is on sale", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/comprar")) == ~p"/"
    end
  end

  describe "with a published edition on sale" do
    setup do
      {edition, _lot} = edition_with_lot(%{venue: "OCA ROOTS"}, %{name: "Lote 1"})
      %{edition: edition}
    end

    test "landing renders the flyer", %{conn: conn, edition: edition} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ edition.name
      assert html =~ "OCA ROOTS"
      assert html =~ "Garantir ingresso"
    end

    test "/comprar renders the buy form with the lot", %{conn: conn} do
      html = conn |> get(~p"/comprar") |> html_response(200)
      assert html =~ "comprar"
      assert html =~ "Lote 1"
    end
  end

  test "static public pages render", %{conn: conn} do
    assert conn |> get(~p"/tocar") |> html_response(200) =~ "Quer tocar"
    assert conn |> get(~p"/avisos") |> html_response(200) =~ "avisos"
    assert conn |> get(~p"/meus-ingressos") |> html_response(200) =~ "Meus ingressos"
  end
end
