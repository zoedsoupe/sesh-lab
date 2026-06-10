defmodule SeshLab.Editions.TicketType do
  @moduledoc """
  Lote de ingresso de uma edição ("Lote 1", "Lista Amiga", "Porta").

  `capacity` é o total histórico (imutável pra estatística); `available` é o
  contador decrementado atomicamente na reserva — mesmo papel do `stock` no
  cozinha_radioativa. Ajustar `capacity` no admin propaga o delta pro
  `available` (nunca abaixo de zero).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Editions.Edition

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ticket_types" do
    belongs_to :edition, Edition

    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :capacity, :integer
    field :available, :integer
    field :is_active, :boolean, default: true
    field :opens_at, :utc_datetime
    field :closes_at, :utc_datetime
    field :position, :integer, default: 0

    timestamps()
  end

  @castable ~w(name description price_cents capacity is_active opens_at closes_at position)a
  @required ~w(name price_cents capacity)a

  def changeset(ticket_type, attrs) do
    ticket_type
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than_or_equal_to: 0)
    |> sync_available()
  end

  # New row: available = capacity. Existing row: capacity delta is applied to
  # available so pending holds and sold counts are preserved.
  defp sync_available(changeset) do
    case fetch_change(changeset, :capacity) do
      :error ->
        changeset

      {:ok, new_capacity} ->
        case changeset.data do
          %__MODULE__{id: nil} ->
            put_change(changeset, :available, new_capacity)

          %__MODULE__{capacity: old_capacity, available: available} ->
            delta = new_capacity - (old_capacity || 0)
            put_change(changeset, :available, max((available || 0) + delta, 0))
        end
    end
  end

  @doc "Lote comprável agora? (ativo + dentro da janela de vendas, se houver)"
  @spec on_sale?(t(), DateTime.t()) :: boolean()
  def on_sale?(%__MODULE__{is_active: false}, _now), do: false

  def on_sale?(%__MODULE__{opens_at: opens, closes_at: closes}, now) do
    after_open = is_nil(opens) or DateTime.compare(now, opens) != :lt
    before_close = is_nil(closes) or DateTime.compare(now, closes) == :lt
    after_open and before_close
  end
end
