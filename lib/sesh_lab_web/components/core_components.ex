defmodule SeshLabWeb.CoreComponents do
  @moduledoc """
  Componentes básicos da UI. Estilo via classes do design system
  (`assets/css/components.css`).
  """

  use Phoenix.Component
  use SeshLabWeb, :verified_routes

  import Phoenix.HTML, only: [raw: 1]

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

  # Order statuses
  defp status_label(:pending), do: "Aguardando"
  defp status_label(:confirmed), do: "Confirmado"
  defp status_label(:cancelled), do: "Cancelado"
  defp status_label(:expired), do: "Expirado"
  # Edition statuses
  defp status_label(:draft), do: "Rascunho"
  defp status_label(:published), do: "Publicada"
  defp status_label(:past), do: "Encerrada"

  @doc "Formata `total_cents` como `R$ 12,34`."
  @spec money(integer()) :: String.t()
  def money(cents) when is_integer(cents) do
    reais = div(cents, 100)
    cents_part = abs(rem(cents, 100)) |> Integer.to_string() |> String.pad_leading(2, "0")
    "R$ #{reais},#{cents_part}"
  end

  # Inlined so the SVG resolves `currentColor` (SESH = --accent por edição) e os
  # stops `var(--lab-*)` do gradiente do "LAB." — ambos quebram via <img>.
  @sesh_logo_path Path.join(:code.priv_dir(:sesh_lab), "static/images/sesh-logo.svg")
  @external_resource @sesh_logo_path
  @sesh_logo_svg File.read!(@sesh_logo_path)

  @doc """
  Logo oficial da SESH (vetor de `Sesh Bandeira 3.svg`, sem o contorno
  rosa-escuro). SESH usa `currentColor` (`--accent` por edição); "LAB." usa um
  gradiente verde→ciano. Inline pra que `currentColor` resolva.

  `src` (arte custom enviada por edição) renderiza como `<img>` cru — sem
  recolor nem tema, só redimensiona. Nil/ausente → cai no vetor oficial.
  """
  attr :class, :string, default: nil
  attr :src, :string, default: nil

  def sesh_logo(%{src: src} = assigns) when is_binary(src) and src != "" do
    ~H"""
    <img src={@src} alt="SESH LAB." class={["sesh-logo sesh-logo--custom", @class]} />
    """
  end

  def sesh_logo(assigns) do
    # Unique gradient id per instance: two inline logos on one page (header +
    # hero) would otherwise share id="lab-grad", and `url(#lab-grad)` resolves
    # to the FIRST match — which is inside the display:none header on hero pages,
    # so the LAB gradient renders empty. Unique-izing severs that cross-ref.
    gid = "lab-grad-#{System.unique_integer([:positive])}"
    svg = String.replace(@sesh_logo_svg, "lab-grad", gid)
    assigns = assign(assigns, :svg, svg)

    ~H"""
    <span class={["sesh-logo", @class]}>{raw(@svg)}</span>
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
