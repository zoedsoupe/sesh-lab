defmodule SeshLab.Tickets.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias SeshLab.Tickets.Order

  @type t :: %__MODULE__{}

  @foreign_key_type :binary_id
  schema "order_items" do
    belongs_to :order, Order, type: :binary_id
    field :ticket_type_id, :binary_id
    field :ticket_type_name_snapshot, :string
    field :merch_item_id, :binary_id
    field :merch_item_name_snapshot, :string
    field :quantity, :integer
    field :unit_price_cents, :integer

    timestamps(updated_at: false)
  end

  @castable ~w(order_id ticket_type_id ticket_type_name_snapshot
               merch_item_id merch_item_name_snapshot quantity unit_price_cents)a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @castable)
    |> validate_required(~w(quantity unit_price_cents)a)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_line_kind()
  end

  @doc "Predicado: a linha e de ingresso?"
  @spec ticket?(t()) :: boolean()
  def ticket?(%__MODULE__{ticket_type_id: id}), do: not is_nil(id)

  @doc "Predicado: a linha e de merch?"
  @spec merch?(t()) :: boolean()
  def merch?(%__MODULE__{merch_item_id: id}), do: not is_nil(id)

  @doc "Nome da linha conforme o tipo (ingresso ou merch)."
  def line_name(%__MODULE__{ticket_type_id: id} = i) when not is_nil(id),
    do: i.ticket_type_name_snapshot

  def line_name(%__MODULE__{} = i), do: i.merch_item_name_snapshot

  defp validate_line_kind(changeset) do
    ticket = get_field(changeset, :ticket_type_id)
    merch = get_field(changeset, :merch_item_id)

    case {ticket, merch} do
      {nil, nil} ->
        add_error(changeset, :ticket_type_id, "linha sem item")

      {t, m} when not is_nil(t) and not is_nil(m) ->
        add_error(changeset, :ticket_type_id, "linha nao pode ser ingresso e merch")

      {t, nil} when not is_nil(t) ->
        validate_required(changeset, [:ticket_type_name_snapshot])

      {nil, _m} ->
        validate_required(changeset, [:merch_item_name_snapshot])
    end
  end
end
