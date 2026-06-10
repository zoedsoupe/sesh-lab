defmodule SeshLab.Coupons.ExpiryWorker do
  @moduledoc """
  Hourly tick that fires "coupon expires tomorrow" pushes via
  `Coupons.notify_expiring/1`. Single-node (SQLite) app, so a plain GenServer
  is enough — no external scheduler. Expiry itself is enforced lazily at
  redemption; this only handles the heads-up notification.
  """

  use GenServer

  alias SeshLab.Coupons

  @interval :timer.hours(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, schedule(), {:continue, :tick}}
  end

  @impl true
  def handle_continue(:tick, state) do
    sweep()
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    sweep()
    {:noreply, schedule(state)}
  end

  defp sweep do
    Coupons.notify_expiring()
  rescue
    e ->
      require Logger
      Logger.error("[coupon_expiry] sweep failed: #{inspect(e)}")
  end

  defp schedule(state \\ nil) do
    Process.send_after(self(), :tick, @interval)
    state
  end
end
