defmodule SeshLab.SettingsTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.Repo
  alias SeshLab.Settings
  alias SeshLab.Settings.Setting

  test "get_bool/2 returns the default when key absent" do
    assert Settings.get_bool("missing", true) == true
    assert Settings.get_bool("missing", false) == false
  end

  test "put_bool/2 then get_bool/2 round-trips true and false" do
    assert {:ok, _} = Settings.put_bool("flag", true)
    assert Settings.get_bool("flag", false) == true

    assert {:ok, _} = Settings.put_bool("flag", false)
    assert Settings.get_bool("flag", true) == false
  end

  test "put_bool/2 twice on same key upserts (one row, latest value)" do
    {:ok, _} = Settings.put_bool("flag", true)
    {:ok, _} = Settings.put_bool("flag", false)

    assert Repo.aggregate(Setting, :count, :key) == 1
    assert Settings.get_bool("flag", true) == false
  end

  test "dj_applications_open?/0 returns true before any write" do
    assert Settings.dj_applications_open?() == true
  end
end
