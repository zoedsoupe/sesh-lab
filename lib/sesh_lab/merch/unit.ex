defmodule SeshLab.Merch.Unit do
  @moduledoc """
  Unidade de merch vendida. So existe apos o pedido confirmado (igual Ticket).
  `code` Crockford base32 (8 chars), unico, ao portador. `redeemed_at` marca
  a retirada unica no balcao (setado atomicamente, igual `used_at` na porta).

  Resgate e separado da porta: nao usa `validate_ticket/1`, tem tela propria.
  """
  use Ecto.Schema

  alias SeshLab.Tickets.Order

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "merch_units" do
    belongs_to :order, Order, type: :binary_id
    field :merch_item_id, :binary_id
    field :merch_item_name_snapshot, :string
    field :sold_edition_id, :binary_id
    field :code, :string
    field :redeemed_at, :utc_datetime

    timestamps()
  end

  @spec display_code(t() | String.t()) :: String.t()
  def display_code(%__MODULE__{code: code}), do: display_code(code)
  def display_code(<<a::binary-size(4), b::binary-size(4)>>), do: a <> "-" <> b
  def display_code(code) when is_binary(code), do: code

  @spec qr_svg(t() | String.t()) :: String.t()
  def qr_svg(%__MODULE__{code: code}), do: qr_svg(code)

  def qr_svg(code) when is_binary(code) do
    code
    |> EQRCode.encode()
    |> EQRCode.svg(width: 220, color: "#05070A", background_color: "#FFFFFF")
  end
end
