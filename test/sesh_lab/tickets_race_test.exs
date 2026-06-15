defmodule SeshLab.TicketsRaceTest do
  @moduledoc """
  Garantias de concorrência via `update_all` atômico (write lock global do
  SQLite): capacidade nunca vende além do lote, e cada ingresso valida uma
  única vez mesmo com porteiros simultâneos.
  """

  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures

  alias SeshLab.{Repo, Tickets}
  alias SeshLab.Editions.TicketType
  alias SeshLab.Tickets.{Order, Ticket}

  test "N concurrent confirmations over K capacity: exactly K succeed" do
    capacity = 3
    callers = 12
    {edition, lot} = edition_with_lot(%{}, %{capacity: capacity})

    # Pending orders hold nothing, so all N can be created; the race is at
    # confirm time, where the atomic decrement decides exactly K winners.
    orders =
      for _ <- 1..callers do
        {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
        order
      end

    parent = self()

    results =
      orders
      |> Enum.map(fn order ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Tickets.confirm_order(order.id)
        end)
      end)
      |> Task.await_many(5_000)

    successes = Enum.count(results, &match?({:ok, %Order{}}, &1))
    soldout = Enum.count(results, &match?({:error, {:sold_out, _}}, &1))

    assert successes == capacity
    assert soldout == callers - capacity
    assert Repo.get!(TicketType, lot.id).available == 0
    assert Repo.aggregate(Ticket, :count, :id) == capacity
  end

  test "two scanners on the same ticket: exactly one validation wins" do
    {edition, lot} = edition_with_lot()
    {:ok, order} = Tickets.create_order(order_attrs(edition, lot))
    {:ok, _} = Tickets.confirm_order(order.id)
    [ticket] = Repo.all(Ticket)
    parent = self()

    results =
      1..20
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Tickets.validate_ticket(ticket.code)
        end)
      end)
      |> Task.await_many(5_000)

    oks = Enum.count(results, &match?({:ok, %Ticket{}}, &1))
    useds = Enum.count(results, &match?({:error, {:already_used, _}}, &1))

    assert oks == 1
    assert useds == 19
  end
end
