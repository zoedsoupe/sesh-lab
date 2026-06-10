defmodule SeshLabWeb.Admin.PromoFormLive do
  use SeshLabWeb, :live_view

  alias SeshLab.{Catalog, Notifications, Promos}
  alias SeshLab.Promos.Promo

  @max_size 5_000_000

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:products, Catalog.list_all_products())
     |> assign_promo(params, socket.assigns.live_action)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: @max_size
     )}
  end

  @impl true
  def handle_event("validate", %{"promo" => params}, socket) do
    qtys = extract_qtys(params, socket.assigns.products)
    params = merge_items(params, socket.assigns.products)

    changeset =
      socket.assigns.promo
      |> Promos.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), qtys: qtys)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("remove-photo", _params, socket) do
    case Promos.update(socket.assigns.promo, %{photo_path: nil}) do
      {:ok, promo} ->
        {:noreply, socket |> put_flash(:info, "foto removida.") |> assign_form(promo)}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Promos.delete(socket.assigns.promo)
    {:noreply, socket |> put_flash(:info, "promo removida.") |> push_navigate(to: ~p"/admin")}
  end

  def handle_event("save", %{"promo" => params}, %{assigns: %{live_action: :new}} = socket) do
    params =
      params
      |> merge_items(socket.assigns.products)
      |> put_photo(socket, "tmp")

    case Promos.create(params) do
      {:ok, promo} ->
        if promo.is_active, do: Notifications.announce_promo(promo)

        {:noreply,
         socket
         |> put_flash(:info, "promo “#{promo.name}” criada.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "não foi possível criar.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"promo" => params}, socket) do
    params =
      params
      |> merge_items(socket.assigns.products)
      |> put_photo(socket, socket.assigns.promo.id)

    case Promos.update(socket.assigns.promo, params) do
      {:ok, promo} ->
        {:noreply,
         socket
         |> put_flash(:info, "promo “#{promo.name}” salva.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "não foi possível salvar.")
         |> assign(form: to_form(changeset))}
    end
  end

  defp assign_promo(socket, _params, :new) do
    assign_form(socket, %Promo{is_active: true, items: []})
  end

  defp assign_promo(socket, %{"id" => id}, :edit) do
    assign_form(socket, Promos.get!(id))
  end

  defp assign_form(socket, promo) do
    qtys = Map.new(promo.items, &{&1.product_id, &1.quantity})

    assign(socket,
      promo: promo,
      page_title: promo.name || "Nova promo",
      form: to_form(Promos.change(promo)),
      qtys: qtys
    )
  end

  defp extract_qtys(params, products) do
    Map.new(products, fn p ->
      {p.id, parse_int(Map.get(params, "qty_" <> p.id))}
    end)
  end

  # Converte os campos `qty_<product_id>` em `items` no formato esperado por
  # `cast_assoc`. Preserva associação existente para evitar duplicatas.
  defp merge_items(params, products) do
    items =
      products
      |> Enum.map(fn p ->
        qty = parse_int(Map.get(params, "qty_" <> p.id))
        {p.id, qty}
      end)
      |> Enum.filter(fn {_, qty} -> qty > 0 end)
      |> Enum.with_index()
      |> Map.new(fn {{pid, qty}, idx} ->
        {to_string(idx), %{"product_id" => pid, "quantity" => qty}}
      end)

    Map.put(params, "items", items)
  end

  defp parse_int(nil), do: 0
  defp parse_int(""), do: 0
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp put_photo(params, socket, pid) do
    case consume_uploaded_entries(socket, :photo, &copy_upload(pid, &1, &2)) do
      [] -> params
      [filename] -> Map.put(params, "photo_path", filename)
    end
  end

  defp copy_upload(pid, %{path: tmp_path}, %{client_name: name}) do
    dir = Catalog.products_dir()
    File.mkdir_p!(dir)
    ext = name |> Path.extname() |> String.downcase() |> sanitize_ext()
    safe_pid = sanitize_slug(pid) || "promo"
    filename = "promo-#{safe_pid}-#{System.system_time(:millisecond)}#{ext}"
    File.cp!(tmp_path, Path.join(dir, filename))
    {:ok, filename}
  end

  defp sanitize_slug(nil), do: nil

  defp sanitize_slug(value) when is_binary(value) do
    case Regex.replace(~r/[^a-z0-9_-]/i, value, "") do
      "" -> nil
      slug -> String.downcase(slug)
    end
  end

  defp sanitize_ext(ext) when ext in ~w(.jpg .jpeg .png .webp), do: ext
  defp sanitize_ext(_), do: ".jpg"

  defp separate_total(qtys, products) do
    Enum.reduce(products, 0, fn p, acc ->
      acc + p.unit_price_cents * Map.get(qtys, p.id, 0)
    end)
  end

  defp form_total_cents(form) do
    case form[:total_cents].value do
      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> 0
        end

      _ ->
        0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <a href={~p"/admin"} class="text-xs text-dim">← painel</a>
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "Nova promo", else: @promo.name}
        </h1>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="stack-3"
          id="promo-form"
          multipart
        >
          <.input
            :if={@live_action == :new}
            field={@form[:id]}
            label="id (slug, ex: kit-festa)"
            required
            autocomplete="off"
          />
          <.input field={@form[:name]} label="nome" required />
          <.input field={@form[:description]} type="textarea" label="descrição" rows="2" />
          <.input
            field={@form[:total_cents]}
            type="number"
            label="preço da promo (centavos)"
            required
            inputmode="numeric"
          />

          <div class="field stack-2">
            <span class="field-label">itens da promo</span>
            <p class="text-xs text-dim">
              quantidade 0 = não inclui. ao menos 1 item obrigatório.
            </p>
            <ul class="stack-2">
              <li :for={p <- @products} class="row space-between align-center">
                <div class="stack-1">
                  <span class="text-sm">{p.name}</span>
                  <span class="text-xs text-dim text-mono">
                    {SeshLabWeb.CoreComponents.money(p.unit_price_cents)}
                  </span>
                </div>
                <input
                  type="number"
                  name={"promo[qty_#{p.id}]"}
                  value={Map.get(@qtys, p.id, 0)}
                  min="0"
                  step="1"
                  inputmode="numeric"
                  class="input"
                  style="max-width: 6rem;"
                />
              </li>
            </ul>
          </div>

          <% sep = separate_total(@qtys, @products) %>
          <% promo_total = form_total_cents(@form) %>
          <p
            :if={sep > 0 and promo_total > 0 and sep > promo_total}
            class="text-xs text-accent"
          >
            separado: {SeshLabWeb.CoreComponents.money(sep)} - economia: {SeshLabWeb.CoreComponents.money(
              sep - promo_total
            )}
          </p>

          <div class="field stack-2">
            <span class="field-label">foto</span>

            <details :if={@promo.photo_path} class="product-detail">
              <summary class="text-xs text-dim">ver foto atual</summary>
              <div class="photo-preview mt-3">
                <img src={Catalog.photo_url(@promo.photo_path)} alt={@promo.name} />
                <button
                  type="button"
                  phx-click="remove-photo"
                  data-confirm="remover foto atual?"
                  class="btn btn--ghost btn--sm"
                >
                  remover
                </button>
              </div>
            </details>

            <label class="dropzone" phx-drop-target={@uploads.photo.ref}>
              <.live_file_input upload={@uploads.photo} class="dropzone-input" />
              <span class="text-xs text-muted">
                {if @promo.photo_path, do: "trocar imagem", else: "enviar imagem"} (jpg/png/webp)
              </span>
            </label>

            <div :for={entry <- @uploads.photo.entries} class="upload-entry">
              <.live_img_preview entry={entry} width="48" />
              <div class="stack-1 flex-1">
                <span class="text-xs text-mono">{entry.client_name}</span>
                <progress class="upload-progress" value={entry.progress} max="100">
                  {entry.progress}%
                </progress>
              </div>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="btn btn--ghost btn--sm"
              >
                cancelar
              </button>
            </div>
          </div>

          <.input field={@form[:is_active]} type="checkbox" label="ativa na vitrine" />

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "criar", else: "salvar"}
          </.button>
        </.form>

        <.button
          :if={@live_action == :edit}
          phx-click="delete"
          data-confirm="apagar esta promo?"
          variant={:danger}
          class="btn--block"
        >
          apagar promo
        </.button>
      </section>
    </Layouts.admin>
    """
  end
end
