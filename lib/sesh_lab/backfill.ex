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

  @doc """
  Lê pedidos **já** backfillados por @handle do Instagram e devolve o link
  direto (`/compra/:id`) de cada um — pra mandar no direct. Não cria nada.

      SeshLab.Backfill.links(1, ["posysavant81", "isinhc", "ju.klem"])

  Aceita handle com ou sem `@`, case-insensitive. Um pedido pode ter vários
  ingressos; o link abre a página do pedido (status + PIX + ingressos).

  Retorna uma lista `%{name:, instagram:, order_id:, url:}`, um por pedido.
  Handles sem pedido somem da saída (confira contra a lista de entrada).
  Pedidos sem instagram (handle vazio no backfill) não casam aqui — busque
  por nome: `Repo.get_by(Order, customer_name: "Pedro Lucas Nogueira")`.
  """
  @spec links(integer(), [String.t()]) :: [map()] | {:error, term()}
  def links(edition_number, handles) when is_integer(edition_number) and is_list(handles) do
    {:ok, _} = Application.ensure_all_started(:sesh_lab)

    case Repo.get_by(Edition, number: edition_number) do
      nil ->
        {:error, {:edition_not_found, edition_number}}

      %Edition{} = edition ->
        wanted = MapSet.new(handles, &norm_handle/1)

        Order
        |> where([o], o.edition_id == ^edition.id)
        |> Repo.all()
        |> Enum.filter(&MapSet.member?(wanted, norm_handle(&1.customer_instagram)))
        |> Enum.map(fn o ->
          %{
            name: o.customer_name,
            instagram: o.customer_instagram,
            order_id: o.id,
            url: order_url(o.id)
          }
        end)
    end
  end

  defp order_url(id), do: SeshLabWeb.Endpoint.url() <> "/compra/#{id}"

  defp norm_handle(nil), do: ""

  defp norm_handle(s),
    do: s |> to_string() |> String.trim() |> String.trim_leading("@") |> String.downcase()

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

    # Abate a disponibilidade atomicamente (relativo + clamp em 0). SET absoluto
    # a partir do `type` carregado em `run/2` é stale: vários compradores do mesmo
    # lote se sobrescrevem e só o último decremento sobrevive.
    from(t in TicketType,
      where: t.id == ^type.id,
      update: [set: [available: fragment("MAX(? - ?, 0)", t.available, ^qty)]]
    )
    |> Repo.update_all([])

    codes = Enum.map(1..qty//1, fn _ -> insert_ticket!(edition, type, order) end)

    %{
      name: buyer[:name],
      lote: type.name,
      qty: qty,
      codes: codes,
      order_id: order.id,
      url: order_url(order.id)
    }
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
