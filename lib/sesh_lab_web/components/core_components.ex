defmodule SeshLabWeb.CoreComponents do
  @moduledoc """
  Componentes básicos da UI. Estilo via classes do design system
  (`assets/css/components.css`).
  """

  use Phoenix.Component

  @doc """
  Botão simples. Variantes: `:primary` (padrão), `:ghost`, `:danger`.
  """
  attr :type, :string, default: "button"
  attr :variant, :atom, default: :primary, values: [:primary, :ghost, :danger]
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value href)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button type={@type} class={["btn", "btn--#{@variant}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Input integrado a `Phoenix.HTML.FormField`. Renderiza label + control + erros.
  """
  attr :id, :string, default: nil
  attr :name, :string
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: []
  attr :required, :boolean, default: false
  attr :prompt, :string, default: nil
  attr :options, :list, default: []
  attr :rest, :global, include: ~w(autocomplete inputmode min max minlength maxlength
                                   pattern placeholder readonly step rows)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="field">
      <label :if={@label} for={@id} class="field-label">{@label}</label>
      <select id={@id} name={@name} class="input" {@rest}>
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="field">
      <label :if={@label} for={@id} class="field-label">{@label}</label>
      <textarea id={@id} name={@name} class="input input--textarea" {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <label class="field field--inline">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class="checkbox"
        {@rest}
      />
      <span class="field-label">{@label}</span>
      <.error :for={msg <- @errors}>{msg}</.error>
    </label>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="field">
      <label :if={@label} for={@id} class="field-label">{@label}</label>
      <input
        type={@type}
        id={@id}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class="input"
        required={@required}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc "Mensagem de erro abaixo de um input."
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="field-error">{render_slot(@inner_block)}</p>
    """
  end

  @doc "Badge para status de pedido."
  attr :status, :atom, required: true
  attr :class, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={["badge", "badge--#{@status}", @class]}>{status_label(@status)}</span>
    """
  end

  defp status_label(:pending), do: "aguardando"
  defp status_label(:confirmed), do: "confirmado"
  defp status_label(:cancelled), do: "cancelado"
  defp status_label(:expired), do: "expirado"

  @doc "Formata `total_cents` como `R$ 12,34`."
  @spec money(integer()) :: String.t()
  def money(cents) when is_integer(cents) do
    reais = div(cents, 100)
    cents_part = abs(rem(cents, 100)) |> Integer.to_string() |> String.pad_leading(2, "0")
    "R$ #{reais},#{cents_part}"
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
