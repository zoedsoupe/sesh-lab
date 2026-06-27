defmodule SeshLabWeb.LojaHTML do
  @moduledoc false
  use SeshLabWeb, :html

  alias SeshLab.Merch

  embed_templates "loja_html/*"

  # Subtler than the ticket lot_row: image, name, price, description, stepper.
  attr :items, :list, required: true
  attr :qtys, :map, required: true

  def store_card(assigns) do
    ~H"""
    <li :for={item <- @items} class="store-card">
      <a
        :if={item.image_path}
        href={Merch.image_url(item.image_path)}
        target="_blank"
        rel="noopener"
        class="store-card-photo"
      >
        <img src={Merch.image_url(item.image_path)} alt={item.name} loading="lazy" />
      </a>
      <div :if={!item.image_path} class="store-card-photo store-card-photo--empty" aria-hidden="true">
        {String.first(item.name)}
      </div>
      <div class="store-card-body stack-2">
        <div class="row space-between align-baseline">
          <span class="text-base">{item.name}</span>
          <span class="text-xs text-dim text-mono">{money(item.price_cents)}</span>
        </div>
        <p :if={item.description not in [nil, ""]} class="text-xs text-dim">{item.description}</p>
        <div class="stepper" data-stepper data-max={item.available}>
          <button type="button" class="stepper-btn" data-stepper-decr aria-label="diminuir">−</button>
          <input
            type="number"
            name={"merch[#{item.id}]"}
            value={Map.get(@qtys, item.id) || Map.get(@qtys, to_string(item.id)) || 0}
            min="0"
            max={item.available}
            step="1"
            inputmode="numeric"
            class="stepper-input"
            data-stepper-input
          />
          <button type="button" class="stepper-btn" data-stepper-incr aria-label="aumentar">+</button>
        </div>
      </div>
    </li>
    """
  end
end
