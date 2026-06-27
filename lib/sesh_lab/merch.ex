defmodule SeshLab.Merch do
  @moduledoc """
  Catalogo de merch (poster, adesivo), estoque, unidades vendidas e resgate no
  balcao.

  Merch e capacidade-limitada igual aos lotes: `stock` total + `available`
  decrementado atomicamente na confirmacao do pedido (`Tickets.confirm_order/2`)
  — pedido pendente nao segura unidade. As unidades (`Unit`) so existem apos o
  pagamento confirmado, cada uma com seu codigo Crockford, resgatavel uma unica
  vez no balcao (`redeem_unit/1`), separado da porta.
  """

  import Ecto.Query

  alias SeshLab.Repo
  alias SeshLab.Merch.{Item, Unit}
  alias SeshLab.Tickets
  alias SeshLab.Tickets.{Order, OrderItem}

  # ── Catalogo ──────────────────────────────────────────────────────────────

  @spec list_items() :: [Item.t()]
  def list_items do
    Item
    |> order_by([m], asc: m.position, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc "Itens vendidos online em /loja (ativos), ordenados por position."
  @spec list_active_items() :: [Item.t()]
  def list_active_items do
    Item
    |> where([m], m.is_active and m.kind == :online)
    |> order_by([m], asc: m.position, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc "Itens vendidos no balcão da festa (ativos), ordenados por position."
  @spec list_counter_items() :: [Item.t()]
  def list_counter_items do
    Item
    |> where([m], m.is_active and m.kind == :counter)
    |> order_by([m], asc: m.position, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc "Itens de balcão ativos por id (pra montar a venda no POS)."
  @spec get_counter_items([Ecto.UUID.t()]) :: [Item.t()]
  def get_counter_items(ids) do
    Item
    |> where([m], m.is_active and m.kind == :counter and m.id in ^ids)
    |> Repo.all()
  end

  @doc "Itens de merch destacados numa edicao (so ativos), ordenados por position."
  @spec list_featured_items(Ecto.UUID.t()) :: [Item.t()]
  def list_featured_items(edition_id) do
    from(m in Item,
      join: e in "edition_merch_items",
      on: e.merch_item_id == m.id,
      where: e.edition_id == ^edition_id and m.is_active,
      order_by: [asc: m.position, asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @spec get_item!(Ecto.UUID.t()) :: Item.t()
  def get_item!(id), do: Repo.get!(Item, id)

  @spec fetch_item(Ecto.UUID.t()) :: {:ok, Item.t()} | :error
  def fetch_item(id) do
    case Repo.get(Item, id) do
      %Item{} = item -> {:ok, item}
      nil -> :error
    end
  end

  @spec change_item(Item.t(), map()) :: Ecto.Changeset.t()
  def change_item(%Item{} = item, attrs \\ %{}), do: Item.changeset(item, attrs)

  @spec create_item(map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_item(Item.t(), map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  @spec toggle_active(Item.t()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def toggle_active(%Item{} = item) do
    update_item(item, %{is_active: not item.is_active})
  end

  # ── Emissao das unidades ────────────────────────────────────────────────────

  @spec mint_units(Order.t(), [OrderItem.t()], (-> String.t())) :: :ok
  def mint_units(%Order{} = order, merch_items, code_fun) do
    Enum.each(merch_items, fn %OrderItem{} = item ->
      for _ <- 1..item.quantity//1, do: insert_unit!(order, item, code_fun, 3)
    end)
  end

  defp insert_unit!(order, item, code_fun, attempts) do
    %Unit{
      order_id: order.id,
      merch_item_id: item.merch_item_id,
      merch_item_name_snapshot: item.merch_item_name_snapshot,
      sold_edition_id: order.edition_id,
      code: code_fun.()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:code)
    |> Repo.insert()
    |> case do
      {:ok, unit} ->
        unit

      {:error, %Ecto.Changeset{errors: [code: _]}} when attempts > 1 ->
        insert_unit!(order, item, code_fun, attempts - 1)

      {:error, cs} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: cs
    end
  end

  # ── Resgate no balcao ─────────────────────────────────────────────────────

  @spec redeem_unit(String.t()) ::
          {:ok, Unit.t()}
          | {:error, {:already_redeemed, DateTime.t()}}
          | {:error, :not_found}
  def redeem_unit(raw_code) do
    code = Tickets.normalize_code(raw_code)
    now = SeshLab.Clock.now_utc()
    query = from u in Unit, where: u.code == ^code and is_nil(u.redeemed_at)

    case Repo.update_all(query, set: [redeemed_at: now, updated_at: now]) do
      {1, _} ->
        {:ok, Repo.get_by!(Unit, code: code)}

      {0, _} ->
        case Repo.get_by(Unit, code: code) do
          nil -> {:error, :not_found}
          %Unit{redeemed_at: at} -> {:error, {:already_redeemed, at}}
        end
    end
  end

  # ── Stats ───────────────────────────────────────────────────────────────────

  @spec sold_count(Ecto.UUID.t()) :: %{sold: non_neg_integer(), redeemed: non_neg_integer()}
  def sold_count(edition_id) do
    from(u in Unit,
      where: u.sold_edition_id == ^edition_id,
      select: %{
        sold: count(u.id),
        redeemed: count(u.id) |> filter(not is_nil(u.redeemed_at))
      }
    )
    |> Repo.one()
  end

  # ── Imagem (upload por produto) ─────────────────────────────────────────────

  @spec image_url(String.t() | nil) :: String.t() | nil
  def image_url(nil), do: nil
  def image_url(filename), do: "/uploads/merch/" <> filename

  @spec merch_dir() :: String.t()
  def merch_dir, do: Path.join(SeshLab.Editions.uploads_dir(), "merch")

  @spec ensure_merch_dir!() :: :ok
  def ensure_merch_dir! do
    File.mkdir_p!(merch_dir())
    :ok
  end
end
