defmodule SeshLab.Release do
  @moduledoc """
  Tasks executed during release deployment.
  """

  @app :sesh_lab

  require Logger

  def seed do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(@app)

    priv_dir = Application.app_dir(@app, "priv")
    seeds_file = Path.join([priv_dir, "repo", "seeds.exs"])

    if File.exists?(seeds_file) do
      Code.eval_file(seeds_file)
    else
      Logger.warning("Seeds file not found at #{seeds_file}")
    end
  end
end
