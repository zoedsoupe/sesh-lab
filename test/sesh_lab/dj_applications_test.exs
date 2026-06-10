defmodule SeshLab.DjApplicationsTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.DjApplications

  @valid %{
    "name" => "DJ Fulano",
    "whatsapp" => "(22) 99999-8888",
    "instagram" => "@FulanoDJ",
    "musical_styles" => "techno, IDM, breakcore",
    "about" => "comecei mês passado, quero testar um set"
  }

  test "create/1 persists, normalizing whatsapp + instagram" do
    assert {:ok, app} = DjApplications.create(@valid)
    assert app.whatsapp == "22999998888"
    assert app.instagram == "fulanodj"
    assert app.musical_styles =~ "techno"
  end

  test "create/1 requires all fields" do
    assert {:error, cs} = DjApplications.create(%{"name" => "x"})
    errors = errors_on(cs)
    assert errors.whatsapp
    assert errors.instagram
    assert errors.musical_styles
    assert errors.about
  end

  test "list/0 returns newest first" do
    {:ok, _} = DjApplications.create(%{@valid | "name" => "DJ Um"})
    {:ok, _} = DjApplications.create(%{@valid | "name" => "DJ Dois"})
    assert ["DJ Dois", "DJ Um"] = DjApplications.list() |> Enum.map(& &1.name)
  end
end
