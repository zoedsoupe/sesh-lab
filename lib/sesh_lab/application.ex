defmodule SeshLab.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Captured at compile time — Mix isn't available at runtime in a release.
  # Workers run everywhere except test (periodic ticks are unwanted there).
  @start_workers Mix.env() != :test

  @impl true
  def start(_type, _args) do
    SeshLab.Editions.ensure_uploads_dir!()

    children =
      [
        SeshLabWeb.Telemetry,
        SeshLab.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:sesh_lab, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:sesh_lab, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SeshLab.PubSub},
        {Finch, name: SeshLab.WebPush.Finch}
      ] ++ workers() ++ [SeshLabWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SeshLab.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SeshLabWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp workers do
    if @start_workers,
      do: [SeshLab.Coupons.ExpiryWorker, SeshLab.Tickets.ExpiryWorker],
      else: []
  end
end
