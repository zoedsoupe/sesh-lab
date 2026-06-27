defmodule SeshLab.Bar.Sale do
  @moduledoc """
  Uma venda de balcão (um checkout): pago na hora, dinheiro ou PIX. Sem cliente,
  sem código, sem Unit — o item é consumido no ato. Imutável (só inserted_at).
  """
  use Ecto.Schema

  alias SeshLab.Bar.SaleItem
  alias SeshLab.Editions.Edition

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bar_sales" do
    field :payment_method, Ecto.Enum, values: [:cash, :pix]
    field :total_cents, :integer

    belongs_to :edition, Edition
    has_many :items, SaleItem, foreign_key: :bar_sale_id

    timestamps(updated_at: false)
  end
end
