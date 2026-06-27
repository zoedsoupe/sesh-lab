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
    # :online → vendido em /loja (PIX async). :counter → vendido no balcão da
    # festa (POS, pago na hora). Mesmo catálogo, canais distintos.
    field :kind, Ecto.Enum, values: [:online, :counter], default: :online
    field :track_stock, :boolean, default: true
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

  @castable ~w(kind track_stock name description price_cents stock image_path is_active position)a
  @required ~w(name price_cents)a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> normalize_tracking()
    |> require_stock_when_tracked()
    |> sync_available()
  end

  # Online sempre rastreia estoque (capacidade). Counter é opcional: sem
  # rastreio, estoque/available ficam 0 e a venda nunca trava.
  defp normalize_tracking(changeset) do
    case get_field(changeset, :kind) do
      :online -> put_change(changeset, :track_stock, true)
      _ -> changeset
    end
  end

  defp require_stock_when_tracked(changeset) do
    if get_field(changeset, :track_stock) do
      changeset
      |> validate_required([:stock])
      |> validate_number(:stock, greater_than_or_equal_to: 0)
    else
      put_change(changeset, :stock, 0)
    end
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
