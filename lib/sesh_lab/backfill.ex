defmodule SeshLab.Backfill do
  @moduledoc """
  Backfill manual de ingressos já vendidos fora do fluxo de PIX (ex: vendas
  combinadas no Instagram antes do site existir).

  Cria pedidos **confirmados**, emite os ingressos (com código/QR de verdade)
  e abate a disponibilidade do lote. NÃO dispara push nem PubSub, e ignora a
  janela de venda (`on_sale?`) — esses lugares já foram vendidos.

  Idempotência: NÃO é idempotente. Rodar duas vezes cria pedidos duplicados.
  Confira a saída antes de repetir.

  ## Uso em produção (Fly)

      fly ssh console -a sesh-lab
      /app/bin/sesh_lab remote

      SeshLab.Backfill.run(1, [
        %{name: "Maria Silva", instagram: "maria.dj", lote: "Lista Amiga", qty: 2},
        %{name: "João Souza",  instagram: "joaobeats", lote: "Lote 1",     qty: 1}
      ])

  `edition` = número da edição (inteiro). Cada comprador: `name`, `instagram`
  (sem @), `lote` (nome do lote, case-insensitive), `qty`.

  Retorna uma lista, um resultado por comprador:
  `%{name:, lote:, qty:, codes: ["ABCD1234", ...]}` em sucesso, ou
  `{:error, motivo, comprador}` em falha (sem afetar os outros).
  """

  import Ecto.Query

  alias SeshLab.Repo
  alias SeshLab.Editions.{Edition, TicketType}
  alias SeshLab.Tickets
  alias SeshLab.Tickets.{Order, OrderItem, Ticket}

  @spec run(integer(), [map()]) :: [map() | {:error, term(), map()}] | {:error, term()}
  def run(edition_number, buyers) when is_integer(edition_number) and is_list(buyers) do
    # Em `eval`/`remote` o app pode não estar de pé; idempotente se já estiver.
    {:ok, _} = Application.ensure_all_started(:sesh_lab)

    case Repo.get_by(Edition, number: edition_number) do
      nil ->
        {:error, {:edition_not_found, edition_number}}

      %Edition{} = edition ->
        types = types_by_name(edition.id)
        Enum.map(buyers, &backfill_one(edition, types, &1))
    end
  end

  defp types_by_name(edition_id) do
    TicketType
    |> where([t], t.edition_id == ^edition_id)
    |> Repo.all()
    |> Map.new(fn t -> {norm(t.name), t} end)
  end

  defp norm(s), do: s |> to_string() |> String.trim() |> String.downcase()

  defp backfill_one(edition, types, buyer) do
    qty = buyer[:qty]
    lote = buyer[:lote]

    cond do
      not (is_integer(qty) and qty > 0) ->
        {:error, {:bad_qty, qty}, buyer}

      is_nil(Map.get(types, norm(lote))) ->
        {:error, {:lote_not_found, lote}, buyer}

      true ->
        type = Map.get(types, norm(lote))

        case Repo.transaction(fn -> do_backfill(edition, type, buyer, qty) end) do
          {:ok, result} -> result
          {:error, reason} -> {:error, reason, buyer}
        end
    end
  end

  defp do_backfill(edition, type, buyer, qty) do
    order =
      %Order{}
      |> Order.changeset(%{
        edition_id: edition.id,
        customer_name: buyer[:name],
        customer_instagram: buyer[:instagram],
        total_cents: type.price_cents * qty,
        status: :confirmed
      })
      |> Repo.insert!()

    %OrderItem{}
    |> OrderItem.changeset(%{
      order_id: order.id,
      ticket_type_id: type.id,
      ticket_type_name_snapshot: type.name,
      quantity: qty,
      unit_price_cents: type.price_cents
    })
    |> Repo.insert!()

    # Abate a disponibilidade (clamp em 0 — esses lugares já saíram).
    new_available = max(type.available - qty, 0)

    Repo.update_all(from(t in TicketType, where: t.id == ^type.id),
      set: [available: new_available]
    )

    codes = Enum.map(1..qty//1, fn _ -> insert_ticket!(edition, type, order) end)
    %{name: buyer[:name], lote: type.name, qty: qty, codes: codes}
  end

  # Mesma estratégia do Tickets.insert_ticket!: retry em colisão de código.
  defp insert_ticket!(edition, type, order, attempts \\ 3) do
    code = Tickets.generate_code()

    %Ticket{
      order_id: order.id,
      ticket_type_id: type.id,
      edition_id: edition.id,
      code: code
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:code)
    |> Repo.insert()
    |> case do
      {:ok, _ticket} ->
        code

      {:error, %Ecto.Changeset{errors: [code: _]}} when attempts > 1 ->
        insert_ticket!(edition, type, order, attempts - 1)

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end
end
