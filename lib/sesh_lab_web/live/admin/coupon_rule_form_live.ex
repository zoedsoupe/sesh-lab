defmodule SeshLabWeb.Admin.CouponRuleFormLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Coupons
  alias SeshLab.Coupons.CouponRule

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_rule(socket, params, socket.assigns.live_action)}
  end

  @impl true
  def handle_event("validate", %{"coupon_rule" => params}, socket) do
    changeset =
      socket.assigns.rule
      |> Coupons.change_rule(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"coupon_rule" => params}, %{assigns: %{live_action: :new}} = socket) do
    case Coupons.create_rule(params) do
      {:ok, _rule} ->
        {:noreply,
         socket |> put_flash(:info, "regra criada.") |> push_navigate(to: ~p"/admin/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"coupon_rule" => params}, socket) do
    case Coupons.update_rule(socket.assigns.rule, params) do
      {:ok, _rule} ->
        {:noreply,
         socket |> put_flash(:info, "regra salva.") |> push_navigate(to: ~p"/admin/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Coupons.delete_rule(socket.assigns.rule)

    {:noreply,
     socket |> put_flash(:info, "regra removida.") |> push_navigate(to: ~p"/admin/cupons")}
  end

  defp assign_rule(socket, _params, :new), do: assign_form(socket, %CouponRule{is_active: true})
  defp assign_rule(socket, %{"id" => id}, :edit), do: assign_form(socket, Coupons.get_rule!(id))

  defp assign_form(socket, rule) do
    assign(socket,
      rule: rule,
      page_title: if(rule.id, do: "editar regra", else: "nova regra"),
      form: to_form(Coupons.change_rule(rule))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <a href={~p"/admin/cupons"} class="text-xs text-dim">← cupons</a>
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "nova regra de cupom", else: "editar regra"}
        </h1>
        <p class="text-xs text-dim">
          emite um cupom automático quando o pedido atinge o valor mínimo.
        </p>

        <.form for={@form} phx-change="validate" phx-submit="save" class="stack-3" id="rule-form">
          <.input field={@form[:name]} label="nome (ex: pedido grande)" required />
          <.input
            field={@form[:min_order_cents]}
            type="number"
            label="pedido mínimo (centavos)"
            required
            inputmode="numeric"
          />
          <.input
            field={@form[:discount_kind]}
            type="select"
            label="tipo de desconto"
            options={[{"porcentagem (%)", "percent"}, {"valor fixo (centavos)", "fixed"}]}
          />
          <.input
            field={@form[:discount_value]}
            type="number"
            label="valor do desconto (% ou centavos)"
            required
            inputmode="numeric"
          />
          <.input
            field={@form[:expires_in_days]}
            type="number"
            label="validade do cupom (dias)"
            inputmode="numeric"
          />
          <.input field={@form[:is_active]} type="checkbox" label="ativa" />

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "criar", else: "salvar"}
          </.button>
        </.form>

        <.button
          :if={@live_action == :edit}
          phx-click="delete"
          data-confirm="apagar esta regra?"
          variant={:danger}
          class="btn--block"
        >
          apagar regra
        </.button>
      </section>
    </Layouts.admin>
    """
  end
end
