defmodule SeshLab.Tickets.ExpiryWorker do
  @moduledoc """
  Sweep de 1 em 1 minuto que expira pedidos pendentes vencidos e devolve a
  capacidade dos lotes (`Tickets.expire_pending/1`). App single-node (SQLite),
  então um GenServer simples basta — sem scheduler externo.
  """

  use GenServer

  alias SeshLab.Tickets

  @interval :timer.minutes(1)

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
    Tickets.expire_pending()
  rescue
    e ->
      require Logger
      Logger.error("[ticket_expiry] sweep failed: #{inspect(e)}")
  end

  defp schedule(state \\ nil) do
    Process.send_after(self(), :tick, @interval)
    state
  end
end
