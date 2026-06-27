defmodule SeshLab.Bar do
  @moduledoc """
  Balcão da festa: POS de consumíveis (cigarro, bebida, água, pirulito) pagos na
  hora. Catálogo é `Merch.Item` com `kind == :counter`; a venda é registrada aqui.

  Core puro monta/valida o carrinho (`build_lines/2`); a casca insere a venda numa
  transação e baixa o estoque dos itens rastreados de forma atômica (guard no
  `update_all`, rollback se acabou). Itens sem rastreio (`track_stock == false`)
  vendem sem travar.
  """
  import Ecto.Query

  alias SeshLab.Bar.{Sale, SaleItem}
  alias SeshLab.Merch
  alias SeshLab.Merch.Item
  alias SeshLab.Repo

  @type cart :: %{optional(String.t()) => integer() | String.t()}

  # ── Venda ─────────────────────────────────────────────────────────────────

  @doc """
  Registra uma venda de balcão. `cart` é `%{item_id => qty}` (qty 0/"" ignorada).
  """
  @spec record_sale(Ecto.UUID.t() | nil, :cash | :pix, cart()) ::
          {:ok, Sale.t()}
          | {:error, :empty_cart | {:sold_out, String.t()} | Ecto.Changeset.t()}
  def record_sale(edition_id, payment_method, cart) when is_map(cart) do
    items = Merch.get_counter_items(item_ids(cart))

    case build_lines(items, cart) do
      {:ok, []} -> {:error, :empty_cart}
      {:ok, lines} -> insert_sale(edition_id, payment_method, lines)
      {:error, _} = err -> err
    end
  end

  # Pure: resolve cada id no item, valida qty e estoque, congela preço/nome.
  @spec build_lines([Item.t()], cart()) ::
          {:ok, [map()]} | {:error, {:sold_out, String.t()}}
  def build_lines(items, cart) do
    by_id = Map.new(items, &{&1.id, &1})

    Enum.reduce_while(cart, {:ok, []}, fn {id, qty}, {:ok, acc} ->
      qty = to_int(qty)

      case Map.fetch(by_id, id) do
        _ when qty <= 0 ->
          {:cont, {:ok, acc}}

        {:ok, %Item{track_stock: true, available: avail, name: name}} when qty > avail ->
          {:halt, {:error, {:sold_out, name}}}

        {:ok, item} ->
          {:cont, {:ok, [line(item, qty) | acc]}}

        :error ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp line(%Item{} = item, qty) do
    %{
      item: item,
      quantity: qty,
      unit_price_cents: item.price_cents,
      line_cents: qty * item.price_cents
    }
  end

  defp insert_sale(edition_id, payment_method, lines) do
    total = Enum.sum_by(lines, & &1.line_cents)

    Repo.transaction(fn ->
      sale =
        Repo.insert!(%Sale{
          edition_id: edition_id,
          payment_method: payment_method,
          total_cents: total
        })

      Enum.each(lines, fn line ->
        Repo.insert!(%SaleItem{
          bar_sale_id: sale.id,
          merch_item_id: line.item.id,
          name_snapshot: line.item.name,
          quantity: line.quantity,
          unit_price_cents: line.unit_price_cents
        })

        decrement(line)
      end)

      sale
    end)
  end

  # Baixa atômica só nos itens rastreados; guard impede vender abaixo de zero.
  defp decrement(%{item: %Item{track_stock: true, id: id}, quantity: qty}) do
    {n, _} =
      from(m in Item,
        where: m.id == ^id and m.available >= ^qty,
        update: [inc: [available: ^(-qty)]]
      )
      |> Repo.update_all([])

    if n == 0, do: Repo.rollback({:sold_out, id})
  end

  defp decrement(_), do: :ok

  defp item_ids(cart), do: for({id, qty} <- cart, to_int(qty) > 0, do: id)

  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  # ── Stats (painel por edição) ───────────────────────────────────────────────

  @doc "Resumo do balcão de uma edição: total, split dinheiro/PIX, top itens."
  @spec stats(Ecto.UUID.t()) :: %{
          total_cents: integer(),
          cash_cents: integer(),
          pix_cents: integer(),
          count: integer(),
          top_items: [%{name: String.t(), qty: integer(), cents: integer()}]
        }
  def stats(edition_id) do
    by_method =
      from(s in Sale,
        where: s.edition_id == ^edition_id,
        group_by: s.payment_method,
        select: {s.payment_method, sum(s.total_cents), count(s.id)}
      )
      |> Repo.all()

    cash = Enum.find_value(by_method, 0, fn {m, c, _} -> m == :cash && c end)
    pix = Enum.find_value(by_method, 0, fn {m, c, _} -> m == :pix && c end)
    count = Enum.sum_by(by_method, fn {_, _, n} -> n end)

    top =
      from(i in SaleItem,
        join: s in Sale,
        on: i.bar_sale_id == s.id,
        where: s.edition_id == ^edition_id,
        group_by: i.name_snapshot,
        order_by: [desc: sum(i.quantity)],
        limit: 5,
        select: %{
          name: i.name_snapshot,
          qty: sum(i.quantity),
          cents: sum(fragment("? * ?", i.quantity, i.unit_price_cents))
        }
      )
      |> Repo.all()

    %{total_cents: cash + pix, cash_cents: cash, pix_cents: pix, count: count, top_items: top}
  end
end
