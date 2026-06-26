defmodule SeshLab.Editions.EditionMerchItem do
  @moduledoc "Join: quais itens de merch aparecem no /comprar de uma edicao."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "edition_merch_items" do
    field :edition_id, :binary_id
    field :merch_item_id, :binary_id
    timestamps(updated_at: false)
  end
end
