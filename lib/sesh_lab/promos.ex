defmodule SeshLab.Promos do
  @moduledoc """
  Promos = bundles de produtos com preço fechado. Expandem em items
  na hora do pedido — reaproveita `Orders.create_order/1` e o
  `reserve_stock` atômico.
  """

  import Ecto.Query

  alias SeshLab.Repo
  alias SeshLab.Promos.{Promo, PromoItem}

  @spec list_active() :: [Promo.t()]
  def list_active do
    Promo
    |> where([p], p.is_active)
    |> order_by(:id)
    |> Repo.all()
    |> Repo.preload(items: :product)
  end

  @spec list_all() :: [Promo.t()]
  def list_all do
    Promo |> order_by(:id) |> Repo.all() |> Repo.preload(items: :product)
  end

  @spec get!(String.t()) :: Promo.t()
  def get!(id), do: Promo |> Repo.get!(id) |> Repo.preload(items: :product)

  @spec get(String.t()) :: Promo.t() | nil
  def get(id) do
    Promo
    |> Repo.get(id)
    |> case do
      nil -> nil
      p -> Repo.preload(p, items: :product)
    end
  end

  @spec create(map()) :: {:ok, Promo.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: %Promo{} |> Promo.changeset(attrs) |> Repo.insert()

  @spec update(Promo.t(), map()) :: {:ok, Promo.t()} | {:error, Ecto.Changeset.t()}
  def update(%Promo{} = promo, attrs) do
    promo |> Repo.preload(:items) |> Promo.admin_changeset(attrs) |> Repo.update()
  end

  @spec delete(Promo.t()) :: {:ok, Promo.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Promo{} = promo), do: Repo.delete(promo)

  @spec change(Promo.t(), map()) :: Ecto.Changeset.t()
  def change(%Promo{} = promo, attrs \\ %{}) do
    promo = Repo.preload(promo, :items)

    if promo.id,
      do: Promo.admin_changeset(promo, attrs),
      else: Promo.changeset(promo, attrs)
  end

  @doc """
  Expande items da promo no formato aceito por `Orders.create_order/1`.
  """
  @spec expand_items(Promo.t()) :: [%{product_id: String.t(), quantity: pos_integer()}]
  def expand_items(%Promo{items: items}) do
    Enum.map(items, fn %PromoItem{product_id: pid, quantity: q} ->
      %{product_id: pid, quantity: q}
    end)
  end

  @doc """
  Soma dos preços avulsos dos items — para mostrar economia vs total da promo.
  """
  @spec separate_total_cents(Promo.t()) :: integer()
  def separate_total_cents(%Promo{items: items}) do
    Enum.reduce(items, 0, fn %PromoItem{quantity: q, product: product}, acc ->
      acc + ((product && product.unit_price_cents) || 0) * q
    end)
  end
end
