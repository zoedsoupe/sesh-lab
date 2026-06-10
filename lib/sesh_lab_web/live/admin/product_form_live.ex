defmodule SeshLabWeb.Admin.ProductFormLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Catalog
  alias SeshLab.Catalog.Product

  @max_size 5_000_000

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_product(params, socket.assigns.live_action)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: @max_size
     )}
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    changeset =
      socket.assigns.product
      |> Catalog.change_product(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("remove-photo", _params, socket) do
    case Catalog.update_product(socket.assigns.product, %{photo_path: nil}) do
      {:ok, product} ->
        {:noreply, socket |> put_flash(:info, "foto removida.") |> assign_form(product)}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Catalog.delete_product(socket.assigns.product)
    {:noreply, socket |> put_flash(:info, "produto removido.") |> push_navigate(to: ~p"/admin")}
  end

  def handle_event("save", %{"product" => params}, %{assigns: %{live_action: :new}} = socket) do
    params = put_photo_for_new(socket, params)

    case Catalog.create_product(params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "produto “#{product.name}” criado.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "não foi possível criar. confira os campos abaixo.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"product" => params}, socket) do
    params = put_photo(socket, params)

    case Catalog.update_product(socket.assigns.product, params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "produto “#{product.name}” salvo.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "não foi possível salvar. confira os campos abaixo.")
         |> assign(form: to_form(changeset))}
    end
  end

  defp assign_product(socket, _params, :new) do
    assign_form(socket, %Product{is_active: true, stock: 0})
  end

  defp assign_product(socket, %{"id" => id}, :edit) do
    assign_form(socket, Catalog.get_product!(id))
  end

  defp assign_form(socket, product) do
    assign(socket,
      product: product,
      page_title: product.name || "novo produto",
      form: to_form(Catalog.change_product(product))
    )
  end

  defp put_photo(socket, params) do
    case consume_uploaded_entries(socket, :photo, &copy_upload(socket.assigns.product.id, &1, &2)) do
      [] -> params
      [filename] -> Map.put(params, "photo_path", filename)
    end
  end

  defp put_photo_for_new(socket, params) do
    pid = sanitize_slug(params["id"]) || "tmp"

    case consume_uploaded_entries(socket, :photo, &copy_upload(pid, &1, &2)) do
      [] -> params
      [filename] -> Map.put(params, "photo_path", filename)
    end
  end

  defp copy_upload(pid, %{path: tmp_path}, %{client_name: name}) do
    dir = Catalog.products_dir()
    File.mkdir_p!(dir)
    ext = name |> Path.extname() |> String.downcase() |> sanitize_ext()
    filename = "#{sanitize_slug(pid) || "img"}-#{System.system_time(:millisecond)}#{ext}"
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <a href={~p"/admin"} class="text-xs text-dim">← painel</a>
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "novo produto", else: @product.name}
        </h1>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="stack-3"
          id="product-form"
          multipart
        >
          <.input
            :if={@live_action == :new}
            field={@form[:id]}
            label="id (slug curto, ex: brownie)"
            required
            autocomplete="off"
          />
          <.input field={@form[:name]} label="nome" required />
          <.input field={@form[:description]} type="textarea" label="descrição" rows="3" />
          <.input
            field={@form[:unit_label]}
            label="rótulo de unidade (ex: unidade, g, saquinho)"
            required
          />
          <.input
            field={@form[:unit_price_cents]}
            type="number"
            label="preço (centavos)"
            required
            inputmode="numeric"
          />
          <.input
            field={@form[:is_preorder]}
            type="checkbox"
            label="encomenda (feito sob pedido, sem estoque)"
          />

          <.input
            :if={preorder?(@form)}
            field={@form[:lead_time_days]}
            type="number"
            label="prazo em dias úteis"
            required
            inputmode="numeric"
          />

          <.input
            :if={not preorder?(@form)}
            field={@form[:stock]}
            type="number"
            label="estoque"
            required
            inputmode="numeric"
          />

          <input :if={preorder?(@form)} type="hidden" name="product[stock]" value="0" />

          <div class="field stack-2">
            <span class="field-label">foto</span>

            <details :if={@product.photo_path} class="product-detail">
              <summary class="text-xs text-dim">ver foto atual</summary>
              <div class="photo-preview mt-3">
                <img src={Catalog.photo_url(@product.photo_path)} alt={@product.name} />
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
                {if @product.photo_path, do: "trocar imagem", else: "enviar imagem"} (jpg/png/webp, até 5 MB)
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
              <p :for={err <- upload_errors(@uploads.photo, entry)} class="field-error">
                {upload_error_message(err)}
              </p>
            </div>

            <p :for={err <- upload_errors(@uploads.photo)} class="field-error">
              {upload_error_message(err)}
            </p>
          </div>

          <.input
            field={@form[:quantity_presets]}
            label="atalhos de quantidade (vírgula, ex: 1,4,12)"
            placeholder="opcional"
            autocomplete="off"
          />

          <.input field={@form[:is_active]} type="checkbox" label="ativo na vitrine" />

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "criar", else: "salvar"}
          </.button>
        </.form>

        <.button
          :if={@live_action == :edit}
          phx-click="delete"
          data-confirm="apagar este produto? itens em pedidos antigos mantêm o nome congelado."
          variant={:danger}
          class="btn--block"
        >
          apagar produto
        </.button>
      </section>
    </Layouts.admin>
    """
  end

  defp upload_error_message(:too_large), do: "arquivo grande demais (máx 5 MB)"
  defp upload_error_message(:not_accepted), do: "formato não aceito (use jpg, png ou webp)"
  defp upload_error_message(:too_many_files), do: "só uma imagem por vez"
  defp upload_error_message(other), do: to_string(other)

  defp preorder?(form) do
    case form[:is_preorder].value do
      true -> true
      "true" -> true
      _ -> false
    end
  end
end
