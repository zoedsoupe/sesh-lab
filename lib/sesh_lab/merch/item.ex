defmodule SeshLab.Merch.Item do
  @moduledoc """
  Item de merch do catalogo global (poster, adesivo). Nao e ingresso e nao
  pertence a uma edicao: o mesmo poster e vendido em varias edicoes.

  `stock` e o total historico (imutavel pra estatistica); `available` e o
  contador decrementado atomicamente na confirmacao do pagamento
  (`Tickets.confirm_order/1`) — pedido pendente nao segura unidade. Mesma
  maquinaria de capacidade dos lotes. `is_active` gate adicional; esgotou e
  para de vender = desativa.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "merch_items" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :stock, :integer
    field :available, :integer
    field :image_path, :string
    field :is_active, :boolean, default: true
    field :position, :integer, default: 0

    timestamps()
  end

  @castable ~w(name description price_cents stock image_path is_active position)a
  @required ~w(name price_cents stock)a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
    |> sync_available()
  end

  # New row: available = stock. Existing row: stock delta applied to available
  # so pending holds / sold counts are preserved. Mirror TicketType's equivalent.
  defp sync_available(changeset) do
    case fetch_change(changeset, :stock) do
      :error ->
        changeset

      {:ok, new_stock} ->
        case changeset.data do
          %__MODULE__{id: nil} ->
            put_change(changeset, :available, new_stock)

          %__MODULE__{stock: old_stock, available: available} ->
            delta = new_stock - (old_stock || 0)
            put_change(changeset, :available, max((available || 0) + delta, 0))
        end
    end
  end
end
