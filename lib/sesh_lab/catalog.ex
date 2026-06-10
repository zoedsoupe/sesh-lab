defmodule SeshLab.Catalog do
  @moduledoc """
  Catálogo de produtos. Schema fixo de 3 produtos no MVP — admin edita
  campos via LiveView, não cria/deleta.
  """

  import Ecto.Query

  alias SeshLab.Repo
  alias SeshLab.Catalog.Product

  @spec list_active_products() :: [Product.t()]
  def list_active_products do
    Product
    |> where([p], p.is_active)
    |> order_by(:id)
    |> Repo.all()
  end

  @doc """
  Particiona produtos ativos em `{pronta_entrega, encomenda}`.
  """
  @spec list_active_partitioned() :: {[Product.t()], [Product.t()]}
  def list_active_partitioned do
    list_active_products() |> Enum.split_with(&(not &1.is_preorder))
  end

  @spec list_all_products() :: [Product.t()]
  def list_all_products do
    Product |> order_by(:id) |> Repo.all()
  end

  @spec get_product!(String.t()) :: Product.t()
  def get_product!(id), do: Repo.get!(Product, id)

  @spec update_product(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update_product(%Product{} = product, attrs) do
    product |> Product.admin_changeset(attrs) |> Repo.update()
  end

  @spec create_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(attrs) do
    %Product{} |> Product.changeset(attrs) |> Repo.insert()
  end

  @spec delete_product(Product.t()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def delete_product(%Product{} = product), do: Repo.delete(product)

  @spec change_product(Product.t(), map()) :: Ecto.Changeset.t()
  def change_product(%Product{} = product, attrs \\ %{}) do
    if product.id,
      do: Product.admin_changeset(product, attrs),
      else: Product.changeset(product, attrs)
  end

  @stock_topic "vitrine:stock"

  @spec stock_topic() :: String.t()
  def stock_topic, do: @stock_topic

  @spec set_stock(String.t(), non_neg_integer()) :: :ok
  def set_stock(id, quantity) when is_binary(id) and is_integer(quantity) and quantity >= 0 do
    {1, _} =
      Product
      |> where(id: ^id)
      |> Repo.update_all(set: [stock: quantity, updated_at: now()])

    broadcast_stock(id, quantity)
    :ok
  end

  @spec broadcast_stock(String.t(), non_neg_integer()) :: :ok
  def broadcast_stock(id, stock) do
    Phoenix.PubSub.broadcast(
      SeshLab.PubSub,
      @stock_topic,
      {:stock_changed, id, stock}
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

  @doc """
  Diretório no disco onde fotos de produtos são salvas.

  Aceita binário (`/data/uploads` em prod) ou `{otp_app, "priv/path"}` (dev).
  """
  @spec uploads_dir() :: String.t()
  def uploads_dir do
    case Application.get_env(
           :sesh_lab,
           :uploads_dir,
           {:sesh_lab, "priv/static/uploads"}
         ) do
      path when is_binary(path) ->
        path

      {app, rel} ->
        Path.join(
          :code.priv_dir(app) |> to_string(),
          Path.relative_to_cwd(rel) |> String.replace_prefix("priv/", "")
        )
    end
  end

  @spec products_dir() :: String.t()
  def products_dir, do: Path.join(uploads_dir(), "products")

  @spec ensure_products_dir!() :: :ok
  def ensure_products_dir! do
    File.mkdir_p!(products_dir())
    :ok
  end

  @spec photo_url(String.t() | nil) :: String.t() | nil
  def photo_url(nil), do: nil
  def photo_url(filename), do: "/uploads/products/" <> filename
end
