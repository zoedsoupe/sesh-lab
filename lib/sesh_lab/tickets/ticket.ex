defmodule SeshLab.Tickets.Ticket do
  @moduledoc """
  Ingresso emitido. Só existe depois do pedido confirmado — por isso a
  validação na porta consulta uma tabela só, sem join com orders.

  `code` é Crockford base32 (8 chars), único, ao portador. `used_at` marca
  entrada única (setado atomicamente na porta).
  """

  use Ecto.Schema

  alias SeshLab.Tickets.Order

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tickets" do
    belongs_to :order, Order, type: :binary_id
    field :ticket_type_id, :binary_id
    field :edition_id, :binary_id
    field :code, :string
    field :used_at, :utc_datetime

    timestamps()
  end

  @doc ~S|Formato de exibição: "XK4M-2PQ7".|
  @spec display_code(t() | String.t()) :: String.t()
  def display_code(%__MODULE__{code: code}), do: display_code(code)

  def display_code(<<a::binary-size(4), b::binary-size(4)>>), do: a <> "-" <> b
  def display_code(code) when is_binary(code), do: code
end
