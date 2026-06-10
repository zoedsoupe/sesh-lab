defmodule SeshLab.Orders do
  @moduledoc """
  Contexto de pedidos. Coração da concorrência de estoque.

  `create_order/1` usa `Ecto.Multi` com `update_all` condicional
  (`where stock >= quantity`) — em SQLite o write lock global torna isso
  atômico e elimina race condition sem `SELECT FOR UPDATE`.
  """

  import Ecto.Query

  alias SeshLab.Repo
  alias SeshLab.Catalog.Product
  alias SeshLab.{Catalog, Coupons, Notifications}
  alias SeshLab.Orders.{Order, OrderItem}
  alias Ecto.Multi

  @typedoc "item de pedido no input de create_order"
  @type item_input :: %{
          required(:product_id) => String.t(),
          required(:quantity) => pos_integer()
        }

  @spec create_order(map()) ::
          {:ok, Order.t()}
          | {:error, {:out_of_stock, String.t()}}
          | {:error, Ecto.Changeset.t()}
  def create_order(attrs) do
    items = normalize_items(attrs)
    products = preload_products(items)

    case validate_items(items, products) do
      :ok ->
        promo_total = attrs[:promo_total_cents] || attrs["promo_total_cents"]
        subtotal = promo_total || total_cents(items, products)

        case resolve_coupon(attrs, promo_total, subtotal) do
          {:ok, coupon, discount} ->
            order_attrs =
              attrs
              |> put_total(subtotal - discount)
              |> put_coupon(coupon && coupon.code, discount)

            Multi.new()
            |> reserve_stock(items, products)
            |> Multi.insert(:order, Order.changeset(%Order{}, order_attrs))
            |> Multi.insert_all(:items, OrderItem, fn %{order: order} ->
              Enum.map(items, &item_attrs(&1, order, products))
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

  # Coupons don't stack on promos. Otherwise validate read-only (discount is
  # recomputed and the coupon is claimed atomically inside the transaction).
  defp resolve_coupon(attrs, promo_total, subtotal) do
    code = attrs[:coupon_code] || attrs["coupon_code"]

    cond do
      code in [nil, ""] -> {:ok, nil, 0}
      not is_nil(promo_total) -> {:error, :no_stacking}
      true -> Coupons.preview(code, %{customer_instagram: instagram(attrs), subtotal: subtotal})
    end
  end

  defp instagram(attrs), do: attrs[:customer_instagram] || attrs["customer_instagram"]

  # Always set server-resolved values so a client can't inject a fake discount.
  defp put_coupon(attrs, code, discount) do
    if Map.has_key?(attrs, "customer_name") do
      attrs |> Map.put("coupon_code", code) |> Map.put("discount_cents", discount)
    else
      attrs |> Map.put(:coupon_code, code) |> Map.put(:discount_cents, discount)
    end
  end

  defp maybe_claim_coupon(multi, nil), do: multi

  defp maybe_claim_coupon(multi, coupon) do
    Multi.run(multi, :claim_coupon, fn repo, %{order: order} ->
      Coupons.claim(repo, coupon, order.id)
    end)
  end

  @doc """
  Maior `lead_time_days_snapshot` entre os items de um pedido. `nil` se
  todos pronta entrega.
  """
  @spec max_lead_time_days(Order.t()) :: pos_integer() | nil
  def max_lead_time_days(%Order{items: items}) when is_list(items) do
    items
    |> Enum.map(& &1.lead_time_days_snapshot)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      values -> Enum.max(values)
    end
  end

  def max_lead_time_days(_), do: nil

  defp put_total(attrs, total) do
    cond do
      Map.has_key?(attrs, "customer_name") -> Map.put(attrs, "total_cents", total)
      true -> Map.put(attrs, :total_cents, total)
    end
  end

  defp normalize_items(attrs) do
    (attrs[:items] || attrs["items"] || [])
    |> Enum.map(fn item ->
      %{
        product_id: item[:product_id] || item["product_id"],
        quantity: to_int(item[:quantity] || item["quantity"])
      }
    end)
    |> Enum.reject(&(&1.quantity in [0, nil]))
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(_), do: 0

  defp preload_products(items) do
    ids = Enum.map(items, & &1.product_id)

    Product
    |> where([p], p.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp validate_items([], _), do: {:error, :empty_cart}

  defp validate_items(items, products) do
    Enum.reduce_while(items, :ok, fn %{product_id: id}, _ ->
      case Map.get(products, id) do
        %Product{is_active: true} -> {:cont, :ok}
        _ -> {:halt, {:error, {:unknown_product, id}}}
      end
    end)
  end

  defp total_cents(items, products) do
    Enum.reduce(items, 0, fn %{product_id: id, quantity: q}, acc ->
      acc + products[id].unit_price_cents * q
    end)
  end

  # Encomenda (preorder) products = made-to-order, stock column ignored —
  # skip reservation entirely. Pronta entrega uses atomic conditional update.
  # Reservation result also carries the post-decrement `remaining` stock so
  # `handle_result/1` can fire an out_of_stock notification when it hits 0.
  defp reserve_stock(multi, items, products) do
    Enum.reduce(items, multi, fn %{product_id: pid, quantity: q}, multi ->
      product = products[pid]

      if product && product.is_preorder do
        Multi.run(multi, {:reserve, pid}, fn _repo, _ ->
          {:ok, %{preorder: true, product_id: pid, product_name: product.name, remaining: nil}}
        end)
      else
        Multi.run(multi, {:reserve, pid}, fn repo, _ ->
          query =
            from p in Product,
              where: p.id == ^pid and p.stock >= ^q,
              select: p.stock

          case repo.update_all(query, inc: [stock: -q]) do
            {1, [remaining]} ->
              {:ok,
               %{
                 preorder: false,
                 product_id: pid,
                 product_name: product.name,
                 remaining: remaining
               }}

            {0, _} ->
              {:error, {:out_of_stock, pid}}
          end
        end)
      end
    end)
  end

  defp item_attrs(%{product_id: pid, quantity: q}, order, products) do
    product = products[pid]
    now = naive_now()

    %{
      order_id: order.id,
      product_id: pid,
      product_name_snapshot: product.name,
      quantity: q,
      unit_price_cents: product.unit_price_cents,
      lead_time_days_snapshot: if(product.is_preorder, do: product.lead_time_days),
      inserted_at: now
    }
  end

  defp handle_result({:ok, %{order: order} = results}) do
    Phoenix.PubSub.broadcast(
      SeshLab.PubSub,
      "admin:orders",
      {:new_order, order.id}
    )

    Notifications.notify_admin_new_order(order)
    broadcast_stock_from_results(results)
    detect_out_of_stock(results)
    Coupons.issue_for_order(order)
    {:ok, order}
  end

  defp handle_result({:error, {:reserve, pid}, {:out_of_stock, pid}, _changes}) do
    {:error, {:out_of_stock, pid}}
  end

  defp handle_result({:error, :claim_coupon, :coupon_taken, _}),
    do: {:error, {:coupon, :coupon_taken}}

  defp handle_result({:error, :order, %Ecto.Changeset{} = cs, _}), do: {:error, cs}
  defp handle_result({:error, _step, reason, _}), do: {:error, reason}

  defp broadcast_stock_from_results(results) do
    Enum.each(results, fn
      {{:reserve, _pid}, %{preorder: false, product_id: pid, remaining: remaining}} ->
        Catalog.broadcast_stock(pid, remaining)

      _ ->
        :ok
    end)
  end

  defp detect_out_of_stock(results) do
    Enum.each(results, fn
      {{:reserve, _pid}, %{preorder: false, remaining: 0, product_id: pid, product_name: name}} ->
        Phoenix.PubSub.broadcast(
          SeshLab.PubSub,
          "admin:orders",
          {:out_of_stock, pid, name}
        )

        Notifications.notify_admin_out_of_stock(pid, name)

      _ ->
        :ok
    end)
  end

  @spec get_order!(Ecto.UUID.t()) :: Order.t()
  def get_order!(id) do
    Order |> Repo.get!(id) |> Repo.preload(:items)
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

  @spec confirm_order(Ecto.UUID.t()) :: {:ok, Order.t()} | {:error, Ecto.Changeset.t()}
  def confirm_order(id) do
    with {:ok, order} <- update_status(id, :confirmed) do
      broadcast(:order_updated, order.id)
      Notifications.notify_customer_order_update(order)
      {:ok, order}
    end
  end

  @spec cancel_order(Ecto.UUID.t()) :: {:ok, Order.t()} | {:error, term()}
  def cancel_order(id) do
    Repo.transaction(fn ->
      order = Repo.get!(Order, id) |> Repo.preload(:items)

      restores =
        if order.status == :pending do
          Enum.flat_map(order.items, &restore_stock/1)
        else
          []
        end

      case update_status(order.id, :cancelled) do
        {:ok, updated} -> {updated, restores}
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> case do
      {:ok, {order, restores}} ->
        Enum.each(restores, fn {pid, stock} -> Catalog.broadcast_stock(pid, stock) end)
        broadcast(:order_updated, order.id)
        Notifications.notify_customer_order_update(order)
        {:ok, order}

      {:error, _} = err ->
        err
    end
  end

  # Skip restore for encomenda items — stock was never decremented.
  defp restore_stock(%OrderItem{lead_time_days_snapshot: lt}) when not is_nil(lt), do: []

  defp restore_stock(%OrderItem{product_id: pid, quantity: q}) do
    query = from p in Product, where: p.id == ^pid, select: p.stock

    case Repo.update_all(query, inc: [stock: q]) do
      {1, [new_stock]} -> [{pid, new_stock}]
      _ -> []
    end
  end

  defp update_status(id, status) do
    Repo.get!(Order, id)
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  defp broadcast(event, id) do
    Phoenix.PubSub.broadcast(SeshLab.PubSub, "admin:orders", {event, id})
  end

  defp naive_now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
