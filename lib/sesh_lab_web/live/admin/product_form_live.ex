defmodule SeshLabWeb.Admin.ProductFormLive do
  use SeshLabWeb, :live_view

  alias SeshLab.Merch
  alias SeshLab.Merch.Item

  @max_image 2_000_000

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_item(params, socket.assigns.live_action)
     |> allow_upload(:image,
       accept: ~w(.png .jpg .jpeg .svg),
       max_entries: 1,
       max_file_size: @max_image
     )}
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset = Merch.change_item(socket.assigns.item, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"item" => params}, %{assigns: %{live_action: :new}} = socket) do
    case Merch.create_item(put_image(params, socket)) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Produto criado.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"item" => params}, socket) do
    case Merch.update_item(socket.assigns.item, put_image(params, socket)) do
      {:ok, _item} ->
        {:noreply, socket |> put_flash(:info, "Produto salvo.") |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("remove-image", _params, socket) do
    {:ok, item} = Merch.update_item(socket.assigns.item, %{"image_path" => nil})
    {:noreply, socket |> put_flash(:info, "Imagem removida.") |> assign_form(item)}
  end

  defp assign_item(socket, _params, :new), do: assign_form(socket, %Item{})

  defp assign_item(socket, %{"id" => id}, :edit) do
    case Merch.fetch_item(id) do
      {:ok, item} ->
        assign_form(socket, item)

      :error ->
        socket
        |> put_flash(:error, "Produto não encontrado.")
        |> push_navigate(to: ~p"/admin/produtos")
    end
  end

  defp assign_form(socket, %Item{} = item) do
    assign(socket,
      item: item,
      page_title: item.name || "Novo produto",
      form: to_form(Merch.change_item(item))
    )
  end

  defp put_image(params, socket) do
    case consume_uploaded_entries(socket, :image, &copy_image/2) do
      [] -> params
      [filename] -> Map.put(params, "image_path", filename)
    end
  end

  defp copy_image(%{path: tmp}, %{client_name: name}) do
    Merch.ensure_merch_dir!()
    ext = name |> Path.extname() |> String.downcase()
    ext = if ext in ~w(.png .jpg .jpeg .svg), do: ext, else: ".png"

    filename =
      "merch-#{System.unique_integer([:positive])}-#{System.system_time(:millisecond)}#{ext}"

    File.cp!(tmp, Path.join(Merch.merch_dir(), filename))
    {:ok, filename}
  end

  defp upload_error_msg(:too_large), do: "Arquivo grande demais (máx 2 MB)"
  defp upload_error_msg(:not_accepted), do: "Formato não aceito (use png, jpg ou svg)"
  defp upload_error_msg(:too_many_files), do: "Só um arquivo"
  defp upload_error_msg(other), do: to_string(other)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "Novo produto", else: @item.name}
        </h1>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          id="product-form"
          class="stack-3"
          multipart
        >
          <.input field={@form[:name]} label="Nome" required />
          <.input field={@form[:description]} type="textarea" label="Descrição" rows="2" />
          <div class="row gap-3">
            <.input
              field={@form[:price_cents]}
              type="number"
              label="Preço (centavos)"
              required
              inputmode="numeric"
            />
            <.input
              field={@form[:stock]}
              type="number"
              label="Estoque total"
              required
              inputmode="numeric"
            />
            <.input field={@form[:position]} type="number" label="Ordem" inputmode="numeric" />
          </div>
          <p :if={@live_action == :edit} class="text-xs text-dim">
            Disponível agora: {@item.available}. Mudar o estoque ajusta o disponível pelo mesmo delta.
          </p>
          <.input field={@form[:is_active]} type="checkbox" label="A venda" />

          <div class="field stack-2">
            <span class="field-label">Imagem (opcional)</span>

            <div :if={@item.image_path} class="photo-preview">
              <img src={Merch.image_url(@item.image_path)} alt="imagem do produto" width="120" />
              <button
                type="button"
                phx-click="remove-image"
                data-confirm="Remover imagem?"
                class="btn btn--ghost btn--sm"
              >
                Remover
              </button>
            </div>

            <label class="dropzone" phx-drop-target={@uploads.image.ref}>
              <.live_file_input upload={@uploads.image} class="dropzone-input" />
              <span class="text-xs text-muted">
                {if @item.image_path, do: "trocar", else: "enviar"} (png/jpg/svg, até 2 MB)
              </span>
            </label>

            <div :for={entry <- @uploads.image.entries} class="upload-entry">
              <span class="text-xs text-mono flex-1">{entry.client_name}</span>
              <progress class="upload-progress" value={entry.progress} max="100">
                {entry.progress}%
              </progress>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="btn btn--ghost btn--sm"
              >
                Cancelar
              </button>
              <p :for={err <- upload_errors(@uploads.image, entry)} class="field-error">
                {upload_error_msg(err)}
              </p>
            </div>

            <p :for={err <- upload_errors(@uploads.image)} class="field-error">
              {upload_error_msg(err)}
            </p>
          </div>

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "Criar produto", else: "Salvar"}
          </.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end
