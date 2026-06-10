defmodule SeshLab.Repo do
  use Ecto.Repo,
    otp_app: :sesh_lab,
    adapter: Ecto.Adapters.SQLite3
end
