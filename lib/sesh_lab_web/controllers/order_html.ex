defmodule SeshLabWeb.OrderHTML do
  @moduledoc false
  use SeshLabWeb, :html

  alias SeshLab.Merch.Unit
  alias SeshLab.Tickets.Ticket

  embed_templates "order_html/*"

  attr :lots, :list, required: true
  attr :items, :map, required: true

  def lot_row(assigns) do
    ~H"""
    <li :for={lot <- @lots} class="qty-row">
      <div class="stack-1">
        <span class="text-base">{lot.name}</span>
        <span class="text-xs text-dim text-mono">{money(lot.price_cents)}</span>
      </div>

      <div class="stepper" data-stepper data-max={lot.available}>
        <button type="button" class="stepper-btn" data-stepper-decr aria-label="diminuir">
          −
        </button>
        <input
          type="number"
          name={"items[#{lot.id}]"}
          value={item_qty(@items, lot.id)}
          min="0"
          max={lot.available}
          step="1"
          inputmode="numeric"
          class="stepper-input"
          data-stepper-input
        />
        <button type="button" class="stepper-btn" data-stepper-incr aria-label="aumentar">
          +
        </button>
      </div>

      <div :if={lot.description not in [nil, ""]} class="lot-req">
        <span class="lot-req-label">Pra usar esse ingresso</span>
        <span class="lot-req-text">{lot.description}</span>
      </div>
    </li>
    """
  end

  attr :merch, :list, required: true
  attr :items, :map, required: true

  def merch_row(assigns) do
    ~H"""
    <li :for={item <- @merch} class="qty-row">
      <img
        :if={item.image_path}
        src={SeshLab.Merch.image_url(item.image_path)}
        alt={item.name}
        loading="lazy"
        class="qty-row-img"
      />

      <div class="stack-1">
        <span class="text-base">{item.name}</span>
        <span class="text-xs text-dim text-mono">{money(item.price_cents)}</span>
      </div>

      <div class="stepper" data-stepper data-max={item.available}>
        <button type="button" class="stepper-btn" data-stepper-decr aria-label="diminuir">
          −
        </button>
        <input
          type="number"
          name={"merch[#{item.id}]"}
          value={item_qty(@items, item.id)}
          min="0"
          max={item.available}
          step="1"
          inputmode="numeric"
          class="stepper-input"
          data-stepper-input
        />
        <button type="button" class="stepper-btn" data-stepper-incr aria-label="aumentar">
          +
        </button>
      </div>

      <div :if={item.description not in [nil, ""]} class="lot-req">
        <span class="lot-req-text">{item.description}</span>
      </div>
    </li>
    """
  end

  def item_qty(items, lot_id) do
    case Map.get(items, lot_id) || Map.get(items, to_string(lot_id)) do
      nil ->
        0

      "" ->
        0

      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s),
          do: (
            {n, _} -> n
            :error -> 0
          )
    end
  end

  @doc "Rótulo curto pro histórico client-side (localStorage): `dd/mm - R$ x`."
  def order_label(order) do
    "#{Calendar.strftime(order.inserted_at, "%d/%m")} - #{money(order.total_cents)}"
  end

  def ticket_display_code(ticket), do: Ticket.display_code(ticket)
  def ticket_qr(ticket), do: Ticket.qr_svg(ticket)

  def merch_qr(unit), do: Unit.qr_svg(unit)
  def merch_display_code(unit), do: Unit.display_code(unit)

  def coupon_label(%{discount_kind: :percent, discount_value: v, expires_at: exp}),
    do: "#{v}% off - vale até #{SeshLab.Clock.format(exp, :date)}"

  def coupon_label(%{discount_kind: :fixed, discount_value: v, expires_at: exp}),
    do: "#{money(v)} off - vale até #{SeshLab.Clock.format(exp, :date)}"

  def status_message(:pending), do: "Aguardando confirmação do PIX"
  def status_message(:confirmed), do: "Ingressos confirmados"
  def status_message(:cancelled), do: "Pedido cancelado"
  def status_message(:expired), do: "Pedido expirado"
end
