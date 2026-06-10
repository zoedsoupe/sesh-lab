defmodule SeshLab.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "products" do
    field :name, :string
    field :description, :string
    field :unit_label, :string
    field :unit_price_cents, :integer
    field :stock, :integer, default: 0
    field :photo_path, :string
    field :is_active, :boolean, default: true
    field :is_preorder, :boolean, default: false
    field :lead_time_days, :integer
    field :quantity_presets, :string

    timestamps()
  end

  @castable ~w(id name description unit_label unit_price_cents stock photo_path
               is_active is_preorder lead_time_days quantity_presets)a
  @required ~w(id name unit_label unit_price_cents)a
  @max_presets 6

  def changeset(product, attrs) do
    product
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
    |> validate_preorder()
    |> normalize_presets()
  end

  def admin_changeset(product, attrs) do
    product
    |> cast(attrs, @castable -- [:id])
    |> validate_required(@required -- [:id])
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
    |> validate_preorder()
    |> normalize_presets()
  end

  defp normalize_presets(changeset) do
    case fetch_change(changeset, :quantity_presets) do
      {:ok, nil} ->
        changeset

      {:ok, raw} ->
        case parse_presets(raw) do
          {:ok, []} ->
            put_change(changeset, :quantity_presets, nil)

          {:ok, list} ->
            put_change(changeset, :quantity_presets, Enum.join(list, ","))

          :error ->
            add_error(
              changeset,
              :quantity_presets,
              "use números positivos separados por vírgula (ex: 1,4,12)"
            )
        end

      :error ->
        changeset
    end
  end

  defp parse_presets(raw) when is_binary(raw) do
    raw
    |> String.split([",", " "], trim: true)
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, acc} ->
      case Integer.parse(token) do
        {n, ""} when n > 0 -> {:cont, {:ok, [n | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, list} ->
        list = list |> Enum.reverse() |> Enum.uniq() |> Enum.take(@max_presets)
        {:ok, list}

      :error ->
        :error
    end
  end

  defp parse_presets(_), do: :error

  @doc "Lista de atalhos de quantidade [1, 4, 12] ou [] se vazio."
  @spec presets_list(t()) :: [pos_integer()]
  def presets_list(%__MODULE__{quantity_presets: nil}), do: []
  def presets_list(%__MODULE__{quantity_presets: ""}), do: []

  def presets_list(%__MODULE__{quantity_presets: s}) when is_binary(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn token ->
      case Integer.parse(String.trim(token)) do
        {n, _} when n > 0 -> [n]
        _ -> []
      end
    end)
  end

  defp validate_preorder(changeset) do
    case get_field(changeset, :is_preorder) do
      true ->
        changeset
        |> validate_required([:lead_time_days],
          message: "obrigatório quando o produto for encomenda"
        )
        |> validate_number(:lead_time_days, greater_than: 0)

      _ ->
        changeset
    end
  end
end
