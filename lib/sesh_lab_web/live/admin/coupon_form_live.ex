defmodule SeshLabWeb.Admin.CouponFormLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Clock, Coupons}
  alias SeshLab.Coupons.Coupon

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_coupon(socket, params, socket.assigns.live_action)}
  end

  @impl true
  def handle_event("validate", %{"coupon" => params}, socket) do
    changeset =
      socket.assigns.coupon
      |> Coupons.change_public_coupon(blank_to_nil(params))
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, form: to_form(changeset), expires_in_days: params["expires_in_days"])}
  end

  def handle_event("save", %{"coupon" => params}, %{assigns: %{live_action: :new}} = socket) do
    attrs = params |> blank_to_nil() |> put_expires_at()

    case Coupons.create_public_coupon(attrs) do
      {:ok, coupon} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cupom #{coupon.code} criado.")
         |> push_navigate(to: ~p"/admin/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"coupon" => params}, socket) do
    attrs = params |> blank_to_nil() |> put_expires_at()

    case Coupons.update_public_coupon(socket.assigns.coupon, attrs) do
      {:ok, _coupon} ->
        {:noreply,
         socket |> put_flash(:info, "Cupom salvo.") |> push_navigate(to: ~p"/admin/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Coupons.delete_coupon(socket.assigns.coupon)

    {:noreply,
     socket |> put_flash(:info, "Cupom removido.") |> push_navigate(to: ~p"/admin/cupons")}
  end

  defp assign_coupon(socket, _params, :new), do: assign_form(socket, %Coupon{is_active: true})

  defp assign_coupon(socket, %{"id" => id}, :edit),
    do: assign_form(socket, Coupons.get_coupon!(id))

  defp assign_form(socket, coupon) do
    assign(socket,
      coupon: coupon,
      page_title: if(coupon.id, do: "Editar cupom", else: "Novo cupom"),
      expires_in_days: "",
      form: to_form(Coupons.change_public_coupon(coupon))
    )
  end

  # Empty optional number/text inputs arrive as "" — drop them so they cast to
  # nil instead of failing integer validation.
  defp blank_to_nil(params) do
    Map.reject(params, fn {_k, v} -> v == "" end)
  end

  defp put_expires_at(params) do
    case Integer.parse(to_string(params["expires_in_days"])) do
      {days, _} when days > 0 ->
        Map.put(params, "expires_at", DateTime.add(Clock.now_utc(), days * 86_400, :second))

      _ ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Cupons" back_to="/admin/cupons">
      <section class="stack-5">
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "Novo cupom público", else: "Editar cupom"}
        </h1>
        <p class="text-xs text-dim">
          Cupom que qualquer cliente pode usar. ao criar (ativo), os inscritos recebem um aviso.
        </p>

        <.form for={@form} phx-change="validate" phx-submit="save" class="stack-3" id="coupon-form">
          <.input
            field={@form[:code]}
            label="Código (vazio = gerar automático)"
            autocomplete="off"
            placeholder="Ex: BLACKFRIDAY10"
          />
          <.input
            field={@form[:discount_kind]}
            type="select"
            label="Tipo de desconto"
            options={[{"Porcentagem (%)", "percent"}, {"Valor fixo (centavos)", "fixed"}]}
          />
          <.input
            field={@form[:discount_value]}
            type="number"
            label="Valor do desconto (% ou centavos)"
            required
            inputmode="numeric"
          />
          <.input
            name="coupon[expires_in_days]"
            value={@expires_in_days}
            type="number"
            label="Validade (dias, vazio = sem expirar)"
            inputmode="numeric"
          />
          <.input
            field={@form[:min_order_cents]}
            type="number"
            label="Pedido mínimo (centavos, opcional)"
            inputmode="numeric"
          />
          <.input
            field={@form[:max_uses]}
            type="number"
            label="Limite de usos (vazio = ilimitado)"
            inputmode="numeric"
          />
          <.input field={@form[:is_active]} type="checkbox" label="Ativo" />

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "Criar", else: "Salvar"}
          </.button>
        </.form>

        <.button
          :if={@live_action == :edit}
          phx-click="delete"
          data-confirm="Apagar este cupom?"
          variant={:danger}
          class="btn--block"
        >
          Apagar cupom
        </.button>
      </section>
    </Layouts.admin>
    """
  end
end
