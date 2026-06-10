# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sesh_lab,
  ecto_repos: [SeshLab.Repo],
  generators: [timestamp_type: :utc_datetime],
  time_zone: "America/Sao_Paulo"

# VAPID keys for Web Push. Generate with: mix sesh.gen.vapid
# Both keys must be URL-safe base64 (no padding).
# subject is a mailto: or https:// URL identifying the application server.
config :sesh_lab, :vapid,
  public_key: nil,
  private_key: nil,
  subject: "mailto:contato@sesh-lab.fly.dev"

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure the endpoint
config :sesh_lab, SeshLabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SeshLabWeb.ErrorHTML, json: SeshLabWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SeshLab.PubSub,
  live_view: [signing_salt: "35RKeJ0K"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sesh_lab: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --loader:.css=css --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
