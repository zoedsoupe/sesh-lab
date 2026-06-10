defmodule SeshLab.SettingsTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.Settings

  describe "get/0" do
    test "creates singleton row when absent" do
      settings = Settings.get()
      assert settings.id == "default"
      assert settings.is_high_demand == false
    end

    test "returns same row on subsequent calls" do
      a = Settings.get()
      b = Settings.get()
      assert a.id == b.id
    end
  end

  describe "high_demand?/0" do
    test "defaults to false" do
      refute Settings.high_demand?()
    end

    test "reflects toggled state" do
      {:ok, _} = Settings.set_high_demand(true)
      assert Settings.high_demand?()
    end
  end

  describe "set_high_demand/1" do
    test "persists value and broadcasts" do
      Phoenix.PubSub.subscribe(SeshLab.PubSub, Settings.topic())

      {:ok, settings} = Settings.set_high_demand(true)
      assert settings.is_high_demand

      assert_receive {:high_demand_changed, true}

      {:ok, settings} = Settings.set_high_demand(false)
      refute settings.is_high_demand
      assert_receive {:high_demand_changed, false}
    end
  end

  describe "toggle_high_demand/0" do
    test "flips current value" do
      {:ok, s1} = Settings.toggle_high_demand()
      assert s1.is_high_demand

      {:ok, s2} = Settings.toggle_high_demand()
      refute s2.is_high_demand
    end
  end
end
