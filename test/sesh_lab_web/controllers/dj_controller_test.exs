defmodule SeshLabWeb.DjControllerTest do
  use SeshLabWeb.ConnCase, async: false

  alias SeshLab.DjApplications
  alias SeshLab.Settings

  test "POST /tocar when closed redirects to ?ok=1 and persists nothing", %{conn: conn} do
    {:ok, _} = Settings.set_dj_applications_open(false)

    params = %{
      "dj_application" => %{
        "name" => "DJ Fulano",
        "whatsapp" => "22999998888",
        "instagram" => "fulanodj",
        "musical_styles" => "techno",
        "about" => "quero tocar"
      }
    }

    conn = post(conn, ~p"/tocar", params)
    assert redirected_to(conn) == ~p"/tocar?ok=1"
    assert DjApplications.list() == []
  end
end
