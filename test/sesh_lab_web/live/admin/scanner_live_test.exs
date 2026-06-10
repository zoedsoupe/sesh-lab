defmodule SeshLabWeb.Admin.ScannerLiveTest do
  use SeshLabWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SeshLab.Fixtures

  alias SeshLab.{Repo, Tickets}
  alias SeshLab.Tickets.Ticket

  setup do
    cfg = Application.fetch_env!(:sesh_lab, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")

    {edition, lot} = edition_with_lot()
    {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
    {:ok, _} = Tickets.confirm_order(order.id)
    [ticket] = Repo.all(Ticket)

    %{auth: auth, edition: edition, ticket: ticket}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "requires basic auth", %{conn: conn} do
    assert get(conn, ~p"/admin/validar").status == 401
  end

  test "shows the door header for the published edition", %{conn: conn, auth: auth} do
    {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/validar")
    assert html =~ "porta"
    assert html =~ "validadas 0 / vendidas 1"
  end

  test "first scan is green, rescan is red (já validado)", %{conn: conn, auth: auth, ticket: t} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/validar")

    html = view |> element("#scanner") |> render_hook("scan", %{"code" => t.code})
    assert html =~ "scan-result--ok"
    assert html =~ "entrou"
    assert html =~ "validadas 1 / vendidas 1"

    html = view |> element("#scanner") |> render_hook("scan", %{"code" => t.code})
    assert html =~ "scan-result--err"
    assert html =~ "já validado"
  end

  test "manual unknown code is not found", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/validar")

    html = view |> form("#scanner form", %{code: "ZZZZZZZZ"}) |> render_submit()
    assert html =~ "scan-result--err"
    assert html =~ "não encontrado"
  end

  test "manual validate accepts a noisy lowercase/hyphenated code", %{
    conn: conn,
    auth: auth,
    ticket: t
  } do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/validar")

    noisy = String.downcase(String.slice(t.code, 0, 4) <> "-" <> String.slice(t.code, 4, 4))
    html = view |> form("#scanner form", %{code: noisy}) |> render_submit()
    assert html =~ "scan-result--ok"
  end
end
