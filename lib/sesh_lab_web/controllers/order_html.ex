defmodule SeshLabWeb.OrderHTML do
  @moduledoc false
  use SeshLabWeb, :html

  embed_templates "order_html/*"

  attr :products, :list, required: true
  attr :items, :map, required: true
  attr :promo, :any, required: true

  def qty_row(assigns) do
    ~H"""
    <li :for={p <- @products} class="qty-row">
      <div class="stack-1">
        <span class="text-base">{p.name}</span>
        <span class="text-xs text-dim text-mono">
          {money(p.unit_price_cents)} / {p.unit_label}
        </span>
        <span :if={p.is_preorder} class="chip chip--encomenda">
          encomenda{if p.lead_time_days, do: " ~ #{p.lead_time_days} dias", else: ""}
        </span>
      </div>

      <div
        :if={is_nil(@promo)}
        class="stepper"
        data-stepper
        data-max={if p.is_preorder, do: "", else: p.stock}
      >
        <button type="button" class="stepper-btn" data-stepper-decr aria-label="diminuir">
          −
        </button>
        <input
          type="number"
          name={"items[#{p.id}]"}
          value={item_qty(@items, p.id)}
          min="0"
          max={if p.is_preorder, do: nil, else: p.stock}
          step="1"
          inputmode="numeric"
          class="stepper-input"
          data-stepper-input
        />
        <button type="button" class="stepper-btn" data-stepper-incr aria-label="aumentar">
          +
        </button>
      </div>

      <div :if={@promo} class="row align-center gap-3">
        <input
          type="hidden"
          name={"items[#{p.id}]"}
          value={item_qty(@items, p.id)}
        />
        <span class="text-mono text-sm">
          {item_qty(@items, p.id)}× {p.unit_label}
        </span>
      </div>

      <% presets = SeshLab.Catalog.Product.presets_list(p) %>
      <div
        :if={is_nil(@promo) and presets != []}
        class="presets"
        data-presets={"items[#{p.id}]"}
      >
        <button
          :for={g <- presets}
          type="button"
          class="preset-btn"
          data-preset-value={g}
        >
          {g}
        </button>
      </div>
    </li>
    """
  end

  def delivery_options do
    [
      {"retirada (pessoalmente)", "retirada"},
      {"entrega (a combinar)", "entrega"}
    ]
  end

  def payment_options do
    [
      {"pix", "pix"},
      {"dinheiro", "dinheiro"},
      {"crédito à vista (link de pagamento será enviado por DM)", "credito"}
    ]
  end

  def item_qty(items, product_id) do
    case Map.get(items, product_id) || Map.get(items, to_string(product_id)) do
      nil ->
        0

      "" ->
        0

      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> 0
        end
    end
  end

  @doc "Rótulo curto pro histórico client-side (localStorage): `dd/mm - R$ x`."
  def order_label(order) do
    "#{Calendar.strftime(order.inserted_at, "%d/%m")} - #{money(order.total_cents)}"
  end

  def coupon_label(%{discount_kind: :percent, discount_value: v, expires_at: exp}),
    do: "#{v}% off - vale até #{SeshLab.Clock.format(exp, :date)}"

  def coupon_label(%{discount_kind: :fixed, discount_value: v, expires_at: exp}),
    do: "#{money(v)} off - vale até #{SeshLab.Clock.format(exp, :date)}"

  def status_message(:pending), do: "aguardando confirmação"
  def status_message(:confirmed), do: "pedido confirmado"
  def status_message(:cancelled), do: "pedido cancelado"
  def status_message(:expired), do: "pedido expirado"
end
