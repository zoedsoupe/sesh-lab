defmodule SeshLab.Tickets do
  @moduledoc """
  Pedidos e ingressos. Coração da concorrência de capacidade.

  Evento pequeno, confirmação manual via Instagram — pedido pendente **não**
  segura capacidade. A baixa de `available` acontece só na confirmação do
  pagamento (`confirm_order/2`), via `update_all` condicional
  (`where available >= quantity`): em SQLite o write lock global torna isso
  atômico e elimina race condition sem `SELECT FOR UPDATE`. Sem reserva, sem
  TTL, sem sweep de expiração.

  Toda transição de status que sai de `:pending` (confirmar, cancelar) é um
  `update_all` com guarda de status + checagem de rows afetadas, então dois
  admins agindo no mesmo pedido nunca brigam.

  Ingressos só existem após confirmação — a validação na porta
  (`validate_ticket/1`) opera numa tabela só, também via `update_all` atômico,
  garantindo entrada única mesmo com dois porteiros escaneando o mesmo QR.
  """

  import Ecto.Query

  alias SeshLab.{Clock, Coupons, Editions, Notifications, Repo}
  alias SeshLab.Editions.TicketType
  alias SeshLab.Tickets.{Order, OrderItem, Ticket}
  alias Ecto.Multi

  # Crockford base32: sem I, L, O, U — nada de ambiguidade na porta.
  @code_alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @code_length 8

  @typedoc "item de pedido no input de create_order"
  @type item_input :: %{
          required(:ticket_type_id) => String.t(),
          required(:quantity) => pos_integer()
        }

  # ── Criação ─────────────────────────────────────────────────────────────────

  @spec create_order(map()) ::
          {:ok, Order.t()}
          | {:error, {:sold_out, String.t()}}
          | {:error, {:not_on_sale, String.t()}}
          | {:error, :empty_cart}
          | {:error, {:unknown_ticket_type, String.t()}}
          | {:error, {:unknown_merch_item, String.t()}}
          | {:error, {:merch_unavailable, String.t()}}
          | {:error, {:merch_sold_out, String.t()}}
          | {:error, {:coupon, term()}}
          | {:error, Ecto.Changeset.t()}
  def create_order(attrs) do
    items = normalize_items(attrs)
    types = preload_types(items)
    merch = preload_merch(items)

    case validate_items(items, types, merch) do
      :ok ->
        subtotal = total_cents(items, types, merch)

        case resolve_coupon(attrs, subtotal) do
          {:ok, coupon, discount} ->
            order_attrs =
              attrs
              |> put_attr(:total_cents, subtotal - discount)
              |> put_attr(:coupon_code, coupon && coupon.code)
              |> put_attr(:discount_cents, discount)

            Multi.new()
            |> Multi.insert(:order, Order.changeset(%Order{}, order_attrs))
            |> Multi.insert_all(:items, OrderItem, fn %{order: order} ->
              Enum.map(items, &item_attrs(&1, order, types, merch))
            end)
            |> maybe_claim_coupon(coupon)
            |> Repo.transaction()
            |> handle_result()

          {:error, reason} ->
            {:error, {:coupon, reason}}
        end

      {:error, _} = err ->
        err
    end
  end

  defp resolve_coupon(attrs, subtotal) do
    code = attrs[:coupon_code] || attrs["coupon_code"]

    if code in [nil, ""] do
      {:ok, nil, 0}
    else
      Coupons.preview(code, %{customer_instagram: instagram(attrs), subtotal: subtotal})
    end
  end

  defp instagram(attrs) do
    Order.normalize_handle(attrs[:customer_instagram] || attrs["customer_instagram"])
  end

  # Always set server-resolved values so a client can't inject fake values.
  defp put_attr(attrs, key, value) do
    if Map.has_key?(attrs, "customer_name") do
      Map.put(attrs, to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end

  defp maybe_claim_coupon(multi, nil), do: multi

  defp maybe_claim_coupon(multi, coupon) do
    Multi.run(multi, :claim_coupon, fn repo, %{order: order} ->
      Coupons.claim(repo, coupon, order.id)
    end)
  end

  defp normalize_items(attrs) do
    raw = attrs[:items] || attrs["items"] || []

    raw
    |> Enum.map(fn item ->
      cond do
        id = item[:ticket_type_id] || item["ticket_type_id"] ->
          %{
            kind: :ticket,
            ticket_type_id: id,
            quantity: to_int(item[:quantity] || item["quantity"])
          }

        id = item[:merch_item_id] || item["merch_item_id"] ->
          %{
            kind: :merch,
            merch_item_id: id,
            quantity: to_int(item[:quantity] || item["quantity"])
          }

        true ->
          %{kind: :unknown, quantity: 0}
      end
    end)
    |> Enum.reject(&(&1.quantity in [0, nil] or &1.kind == :unknown))
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(_), do: 0

  defp preload_types(items) do
    ids = for %{kind: :ticket, ticket_type_id: id} <- items, do: id

    TicketType
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp preload_merch(items) do
    ids = for %{kind: :merch, merch_item_id: id} <- items, do: id

    SeshLab.Merch.Item
    |> where([m], m.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp validate_items([], _types, _merch), do: {:error, :empty_cart}

  # Soft gate at order time (good UX): reject obvious sold-out / closed lots.
  # Não é autoritativo — dois pendentes podem passar no mesmo último lugar; a
  # baixa atômica em `confirm_order/2` é quem decide de verdade.
  defp validate_items(items, types, merch) do
    now = Clock.now_utc()

    Enum.reduce_while(items, :ok, fn item, _ ->
      case item do
        %{kind: :ticket, ticket_type_id: id, quantity: q} ->
          case Map.get(types, id) do
            nil ->
              {:halt, {:error, {:unknown_ticket_type, id}}}

            %TicketType{} = type ->
              cond do
                not TicketType.on_sale?(type, now) -> {:halt, {:error, {:not_on_sale, id}}}
                type.available < q -> {:halt, {:error, {:sold_out, id}}}
                true -> {:cont, :ok}
              end
          end

        %{kind: :merch, merch_item_id: id, quantity: q} ->
          case Map.get(merch, id) do
            nil -> {:halt, {:error, {:unknown_merch_item, id}}}
            %{is_active: false} -> {:halt, {:error, {:merch_unavailable, id}}}
            %{available: avail} when avail < q -> {:halt, {:error, {:merch_sold_out, id}}}
            _ -> {:cont, :ok}
          end
      end
    end)
  end

  defp total_cents(items, types, merch) do
    Enum.reduce(items, 0, fn item, acc ->
      case item do
        %{kind: :ticket, ticket_type_id: id, quantity: q} -> acc + types[id].price_cents * q
        %{kind: :merch, merch_item_id: id, quantity: q} -> acc + merch[id].price_cents * q
      end
    end)
  end

  # Both clauses emit the same column set (irrelevant FK left nil) so insert_all
  # gets uniform row maps; SQLite rejects cell-wise defaults from ragged maps.
  defp item_attrs(%{kind: :ticket, ticket_type_id: id, quantity: q}, order, types, _merch) do
    type = types[id]

    %{
      order_id: order.id,
      ticket_type_id: id,
      ticket_type_name_snapshot: type.name,
      merch_item_id: nil,
      merch_item_name_snapshot: nil,
      quantity: q,
      unit_price_cents: type.price_cents,
      inserted_at: Clock.now_utc() |> DateTime.to_naive()
    }
  end

  defp item_attrs(%{kind: :merch, merch_item_id: id, quantity: q}, order, _types, merch) do
    m = merch[id]

    %{
      order_id: order.id,
      ticket_type_id: nil,
      ticket_type_name_snapshot: nil,
      merch_item_id: id,
      merch_item_name_snapshot: m.name,
      quantity: q,
      unit_price_cents: m.price_cents,
      inserted_at: Clock.now_utc() |> DateTime.to_naive()
    }
  end

  defp handle_result({:ok, %{order: order}}) do
    broadcast(:new_order, order.id)
    Notifications.notify_admin_new_order(order)
    Coupons.issue_for_order(order)
    {:ok, order}
  end

  defp handle_result({:error, :claim_coupon, :coupon_taken, _}),
    do: {:error, {:coupon, :coupon_taken}}

  defp handle_result({:error, :order, %Ecto.Changeset{} = cs, _}), do: {:error, cs}
  defp handle_result({:error, _step, reason, _}), do: {:error, reason}

  # ── Confirmação / emissão ───────────────────────────────────────────────────

  @doc """
  Confirma o pagamento, baixa a capacidade e emite os ingressos (um row por
  unidade).

  É aqui — e só aqui — que `available` cai, via `update_all` condicional
  (`where available >= quantity`). Como pedidos pendentes não seguram lugar,
  dois podem ter sido criados pro mesmo último ingresso; o primeiro a confirmar
  leva e o segundo recebe `{:error, {:sold_out, id}}`. A transição
  `pending -> confirmed` tem guarda de status: se outro admin cancelou/confirmou
  antes, retorna `{:error, :not_pending}` e nada é emitido.

  `opts[:code_fun]` injeta o gerador de código (testes de colisão).
  """
  @spec confirm_order(Ecto.UUID.t(), keyword()) ::
          {:ok, Order.t()}
          | {:error, :not_pending}
          | {:error, {:sold_out, String.t()}}
          | {:error, {:merch_sold_out, String.t()}}
          | {:error, term()}
  def confirm_order(id, opts \\ []) do
    code_fun = Keyword.get(opts, :code_fun, &generate_code/0)

    Repo.transaction(fn ->
      case transition(id, from: :pending, to: :confirmed) do
        :ok ->
          order = get_order!(id)
          claim_capacity!(order)
          claim_merch!(order)
          issue_tickets(order, code_fun)
          mint_merch(order, code_fun)
          order

        :stale ->
          Repo.rollback(:not_pending)
      end
    end)
    |> case do
      {:ok, order} ->
        order = get_order!(order.id)
        broadcast(:order_updated, order.id)
        detect_soldout(order)
        Notifications.notify_customer_order_update(order)
        {:ok, order}

      {:error, _} = err ->
        err
    end
  end

  @typedoc "input to issue_confirmed/2"
  @type comp_input :: %{
          required(:edition_id) => Ecto.UUID.t(),
          required(:ticket_type_id) => Ecto.UUID.t(),
          required(:customer_name) => String.t(),
          required(:customer_instagram) => String.t(),
          required(:quantity) => pos_integer()
        }

  @doc """
  Emits a confirmed order with N real tickets against a lote, decrementing its
  `available` atomically (relative + clamp at 0). Unlike confirm_order/2 this does
  NOT gate on `is_active`, so it works for cortesia lotes. Bypasses sale window and
  the pending-hold flow by design. `opts[:notify?]` (default false) broadcasts
  :new_order so the dashboard refreshes. `opts[:code_fun]` injects the code
  generator (collision tests). Admin emission is authoritative over the comp lote's
  headcount: never rolls back on shortage, available just clamps at 0.
  """
  @spec issue_confirmed(comp_input(), keyword()) ::
          {:ok, %{order: Order.t(), codes: [String.t()]}}
          | {:error, Ecto.Changeset.t() | term()}
  def issue_confirmed(input, opts \\ []) do
    notify? = Keyword.get(opts, :notify?, false)
    code_fun = Keyword.get(opts, :code_fun, &generate_code/0)
    qty = input.quantity
    type = Editions.get_ticket_type!(input.ticket_type_id)

    Repo.transaction(fn ->
      order =
        %Order{}
        |> Order.changeset(%{
          edition_id: input.edition_id,
          customer_name: input.customer_name,
          customer_instagram: input.customer_instagram,
          total_cents: type.price_cents * qty,
          status: :confirmed
        })
        |> Repo.insert()
        |> case do
          {:ok, order} -> order
          {:error, cs} -> Repo.rollback(cs)
        end

      item =
        %OrderItem{}
        |> OrderItem.changeset(%{
          order_id: order.id,
          ticket_type_id: type.id,
          ticket_type_name_snapshot: type.name,
          quantity: qty,
          unit_price_cents: type.price_cents
        })
        |> Repo.insert!()

      from(t in TicketType,
        where: t.id == ^type.id,
        update: [set: [available: fragment("MAX(? - ?, 0)", t.available, ^qty)]]
      )
      |> Repo.update_all([])

      codes =
        for _ <- 1..qty//1 do
          ticket = insert_ticket!(order, item, code_fun, 3)
          ticket.code
        end

      %{order: order, codes: codes}
    end)
    |> case do
      {:ok, %{order: order} = result} ->
        if notify?, do: broadcast(:new_order, order.id)
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  # Atomic conditional decrement at confirm time. Rolls the whole confirmation
  # back (no tickets, status stays pending) if any lot can't cover the quantity.
  defp claim_capacity!(%Order{items: items}) do
    items
    |> Enum.filter(&OrderItem.ticket?/1)
    |> Enum.each(fn %OrderItem{ticket_type_id: id, quantity: q} ->
      query = from t in TicketType, where: t.id == ^id and t.available >= ^q and t.is_active

      case Repo.update_all(query, inc: [available: -q]) do
        {1, _} -> :ok
        {0, _} -> Repo.rollback({:sold_out, id})
      end
    end)
  end

  # Atomic merch stock claim at confirm time, parallel to claim_capacity!/1.
  # Queries Merch.Item; a shortage rolls the whole confirmation back.
  defp claim_merch!(%Order{items: items}) do
    items
    |> Enum.filter(&OrderItem.merch?/1)
    |> Enum.each(fn %OrderItem{merch_item_id: id, quantity: q} ->
      query = from m in SeshLab.Merch.Item, where: m.id == ^id and m.available >= ^q

      case Repo.update_all(query, inc: [available: -q]) do
        {1, _} -> :ok
        {0, _} -> Repo.rollback({:merch_sold_out, id})
      end
    end)
  end

  # Fire soldout notification for any lot this confirmation drove to zero.
  defp detect_soldout(%Order{items: items}) do
    items
    |> Enum.filter(&OrderItem.ticket?/1)
    |> Enum.each(fn %OrderItem{ticket_type_id: id} ->
      case Repo.get(TicketType, id) do
        %TicketType{available: 0} = type ->
          broadcast(:soldout, type.id)
          Notifications.notify_admin_soldout(type)

        _ ->
          :ok
      end
    end)
  end

  defp issue_tickets(%Order{} = order, code_fun) do
    order.items
    |> Enum.filter(&OrderItem.ticket?/1)
    |> Enum.each(fn %OrderItem{} = item ->
      for _ <- 1..item.quantity do
        insert_ticket!(order, item, code_fun, _attempts = 3)
      end
    end)
  end

  defp mint_merch(%Order{} = order, code_fun) do
    merch_lines = Enum.filter(order.items, &OrderItem.merch?/1)
    SeshLab.Merch.mint_units(order, merch_lines, code_fun)
  end

  defp insert_ticket!(order, item, code_fun, attempts) do
    %Ticket{
      order_id: order.id,
      ticket_type_id: item.ticket_type_id,
      edition_id: order.edition_id,
      code: code_fun.()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:code)
    |> Repo.insert()
    |> case do
      {:ok, ticket} ->
        ticket

      {:error, %Ecto.Changeset{errors: [code: _]}} when attempts > 1 ->
        insert_ticket!(order, item, code_fun, attempts - 1)

      {:error, cs} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: cs
    end
  end

  @doc "Código Crockford base32 de #{@code_length} chars (40 bits de entropia)."
  @spec generate_code() :: String.t()
  def generate_code do
    # 256 = 8 × 32, então rem/2 por byte é uniforme no alfabeto.
    for <<byte <- :crypto.strong_rand_bytes(@code_length)>>, into: "" do
      <<Enum.at(@code_alphabet, rem(byte, 32))>>
    end
  end

  # ── Validação na porta ──────────────────────────────────────────────────────

  @doc """
  Valida (e queima) um ingresso pelo código. Entrada única: o `update_all`
  condicional em `used_at IS NULL` garante exatamente uma validação por
  código, mesmo com scanners concorrentes.
  """
  @spec validate_ticket(String.t()) ::
          {:ok, Ticket.t()}
          | {:error, {:already_used, DateTime.t()}}
          | {:error, :not_found}
  def validate_ticket(raw_code) do
    code = normalize_code(raw_code)
    now = Clock.now_utc()

    query = from t in Ticket, where: t.code == ^code and is_nil(t.used_at)

    case Repo.update_all(query, set: [used_at: now, updated_at: now]) do
      {1, _} ->
        ticket = Repo.get_by!(Ticket, code: code) |> Repo.preload([:order])
        broadcast_door(ticket.edition_id)
        {:ok, ticket}

      {0, _} ->
        case Repo.get_by(Ticket, code: code) do
          nil -> {:error, :not_found}
          %Ticket{used_at: at} -> {:error, {:already_used, at}}
        end
    end
  end

  @doc """
  Normaliza input da porta: upcase, remove separadores e mapeia os
  caracteres excluídos do alfabeto Crockford (O→0, I/L→1).
  """
  @spec normalize_code(String.t()) :: String.t()
  def normalize_code(raw) do
    raw
    |> String.upcase()
    |> String.replace(~r/[\s-]/, "")
    |> String.replace("O", "0")
    |> String.replace(~r/[IL]/, "1")
  end

  # ── Cancelamento / expiração ────────────────────────────────────────────────

  @doc """
  Cancela um pedido. Pendente não segura capacidade, então só muda o status;
  confirmado devolve a capacidade baixada e deleta os ingressos emitidos (a
  porta passa a responder "não encontrado").
  """
  @spec cancel_order(Ecto.UUID.t()) :: {:ok, Order.t()} | {:error, :not_cancellable}
  def cancel_order(id) do
    Repo.transaction(fn ->
      cond do
        transition(id, from: :pending, to: :cancelled) == :ok ->
          get_order!(id)

        transition(id, from: :confirmed, to: :cancelled) == :ok ->
          order = get_order!(id)
          restore_capacity(order)
          restore_merch(order)
          from(t in Ticket, where: t.order_id == ^order.id) |> Repo.delete_all()
          from(u in SeshLab.Merch.Unit, where: u.order_id == ^order.id) |> Repo.delete_all()
          order

        true ->
          Repo.rollback(:not_cancellable)
      end
    end)
    |> case do
      {:ok, order} ->
        order = get_order!(order.id)
        broadcast(:order_updated, order.id)
        Notifications.notify_customer_order_update(order)
        {:ok, order}

      {:error, _} = err ->
        err
    end
  end

  # Guarded status transition: only succeeds if the order is still in `from`.
  defp transition(id, from: from, to: to) do
    now = Clock.now_utc()
    query = from o in Order, where: o.id == ^id and o.status == ^from

    case Repo.update_all(query, set: [status: to, updated_at: now]) do
      {1, _} -> :ok
      {0, _} -> :stale
    end
  end

  defp restore_capacity(%Order{items: items}) do
    items
    |> Enum.filter(&OrderItem.ticket?/1)
    |> Enum.each(fn %OrderItem{ticket_type_id: id, quantity: q} ->
      from(t in TicketType, where: t.id == ^id)
      |> Repo.update_all(inc: [available: q])
    end)
  end

  defp restore_merch(%Order{items: items}) do
    items
    |> Enum.filter(&OrderItem.merch?/1)
    |> Enum.each(fn %OrderItem{merch_item_id: id, quantity: q} ->
      from(m in SeshLab.Merch.Item, where: m.id == ^id)
      |> Repo.update_all(inc: [available: q])
    end)
  end

  # ── Queries ─────────────────────────────────────────────────────────────────

  @spec get_order!(Ecto.UUID.t()) :: Order.t()
  def get_order!(id) do
    Order |> Repo.get!(id) |> Repo.preload([:items, :tickets, :merch_units])
  end

  @spec list_recent(non_neg_integer()) :: [Order.t()]
  def list_recent(limit \\ 50) do
    Order
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:items)
  end

  @spec list_pending() :: [Order.t()]
  def list_pending do
    Order
    |> where(status: :pending)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Repo.preload(:items)
  end

  @doc """
  Busca pedidos por handle do Instagram (prefixo, já normalizado lowercase/sem @)
  ou por nome (substring, case-insensitive ASCII). Não filtra por edição — o ponto
  é achar pedidos antigos/de outra edição (ex: alguém manda DM pedindo o link).

  Termo < 2 chars devolve `[]`, pra não varrer a tabela inteira a cada tecla.

  # ponytail: SQLite LIKE é case-insensitive só pra ASCII; nome com acento
  # (José buscado como "jose") não casa. Handle é o identificador de fato e o
  # caminho principal, então aceitável. Gatilho pra revisitar: precisar de busca
  # accent-insensitive (aí vira coluna normalizada ou collation).
  """
  @spec search_orders(String.t(), keyword()) :: [Order.t()]
  def search_orders(term, opts \\ []) when is_binary(term) do
    term = String.trim(term)

    if String.length(term) < 2 do
      []
    else
      limit = Keyword.get(opts, :limit, 30)
      handle = Order.normalize_handle(term) <> "%"
      name_pat = "%" <> term <> "%"

      Order
      |> where([o], like(o.customer_name, ^name_pat) or like(o.customer_instagram, ^handle))
      |> order_by(desc: :inserted_at)
      |> limit(^limit)
      |> Repo.all()
      |> Repo.preload(:items)
    end
  end

  @doc """
  Números da edição pro dashboard e pra porta:
  vendido confirmado / pendente segurando / disponível / validadas.
  """
  @spec stats(Ecto.UUID.t()) :: %{
          capacity: non_neg_integer(),
          available: non_neg_integer(),
          held_pending: non_neg_integer(),
          sold_confirmed: non_neg_integer(),
          revenue_cents: non_neg_integer(),
          validated: non_neg_integer()
        }
  def stats(edition_id) do
    # ponytail: stats headline = paid seats only; comps live in is_active:false
    # lotes, still visible via stats_by_type/1.
    %{capacity: cap, available: avail} =
      from(t in TicketType,
        where: t.edition_id == ^edition_id and t.is_active,
        select: %{
          capacity: coalesce(sum(t.capacity), 0),
          available: coalesce(sum(t.available), 0)
        }
      )
      |> Repo.one()

    held =
      from(i in OrderItem,
        join: o in Order,
        on: o.id == i.order_id,
        where:
          o.edition_id == ^edition_id and o.status == :pending and
            not is_nil(i.ticket_type_id),
        select: coalesce(sum(i.quantity), 0)
      )
      |> Repo.one()

    sold =
      from(i in OrderItem,
        join: o in Order,
        on: o.id == i.order_id,
        where:
          o.edition_id == ^edition_id and o.status == :confirmed and
            not is_nil(i.ticket_type_id),
        select: coalesce(sum(i.quantity), 0)
      )
      |> Repo.one()

    validated =
      from(t in Ticket,
        where: t.edition_id == ^edition_id and not is_nil(t.used_at),
        select: count(t.id)
      )
      |> Repo.one()

    # Revenue = total actually charged on confirmed orders (post-coupon), so
    # order-level discounts are reflected. Per-lote revenue would sum OrderItem.
    revenue =
      from(o in Order,
        where: o.edition_id == ^edition_id and o.status == :confirmed,
        select: coalesce(sum(o.total_cents), 0)
      )
      |> Repo.one()

    %{
      capacity: cap,
      available: avail,
      held_pending: held,
      sold_confirmed: sold,
      revenue_cents: revenue,
      validated: validated
    }
  end

  @doc """
  Stats por lote pra montar a tabela do dashboard. Mapa
  `type_id => %{held, sold, validated}` (capacity/available já vêm no
  `%TicketType{}`). Dois grouped queries, sem N+1.
  """
  @spec stats_by_type(Ecto.UUID.t()) ::
          %{
            optional(Ecto.UUID.t()) => %{
              held: non_neg_integer(),
              sold: non_neg_integer(),
              validated: non_neg_integer()
            }
          }
  def stats_by_type(edition_id) do
    base = %{held: 0, sold: 0, validated: 0}

    item_counts =
      from(i in OrderItem,
        join: o in Order,
        on: o.id == i.order_id,
        where:
          o.edition_id == ^edition_id and o.status in [:pending, :confirmed] and
            not is_nil(i.ticket_type_id),
        group_by: [i.ticket_type_id, o.status],
        select: {i.ticket_type_id, o.status, coalesce(sum(i.quantity), 0)}
      )
      |> Repo.all()

    validated =
      from(t in Ticket,
        where: t.edition_id == ^edition_id and not is_nil(t.used_at),
        group_by: t.ticket_type_id,
        select: {t.ticket_type_id, count(t.id)}
      )
      |> Repo.all()

    acc =
      Enum.reduce(item_counts, %{}, fn {type_id, status, qty}, acc ->
        key = if status == :pending, do: :held, else: :sold
        row = Map.get(acc, type_id, base)
        Map.put(acc, type_id, %{row | key => qty})
      end)

    Enum.reduce(validated, acc, fn {type_id, n}, acc ->
      row = Map.get(acc, type_id, base)
      Map.put(acc, type_id, %{row | validated: n})
    end)
  end

  # ── PubSub ──────────────────────────────────────────────────────────────────

  defp broadcast(event, id) do
    Phoenix.PubSub.broadcast(SeshLab.PubSub, "admin:orders", {event, id})
  end

  defp broadcast_door(edition_id) do
    Phoenix.PubSub.broadcast(SeshLab.PubSub, "door:#{edition_id}", {:validated, edition_id})
  end
end
