defmodule SeshLabWeb.Admin.EditionFormLive do
  use SeshLabWeb, :live_view

  alias Phoenix.LiveView.JS
  alias SeshLab.{Clock, Editions, Merch, Notifications}
  alias SeshLab.Editions.Edition

  @max_logo 2_000_000

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_edition(params, socket.assigns.live_action)
     |> allow_upload(:logo, accept: ~w(.svg .png), max_entries: 1, max_file_size: @max_logo)}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"edition" => params}, socket) do
    changeset =
      socket.assigns.edition
      |> Editions.change_edition(to_utc(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), starts_at_local: params["starts_at"])}
  end

  def handle_event("save", %{"edition" => params}, %{assigns: %{live_action: :new}} = socket) do
    params = params |> to_utc() |> put_logo(socket, params["number"])

    case Editions.create_edition(params) do
      {:ok, edition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Edição “#{edition.name}” criada. Publique quando estiver pronta.")
         |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos abaixo.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"edition" => params}, socket) do
    edition = socket.assigns.edition
    params = params |> to_utc() |> put_logo(socket, to_string(edition.number))

    case Editions.update_edition(edition, params) do
      {:ok, _edition} ->
        {:noreply, socket |> put_flash(:info, "Edição salva.") |> push_navigate(to: ~p"/admin")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, error_flash(changeset))
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("publish", _params, socket) do
    case Editions.publish(socket.assigns.edition) do
      {:ok, edition} ->
        Notifications.announce_edition(edition)

        {:noreply,
         socket
         |> put_flash(:info, "Edição publicada (qualquer outra publicada foi arquivada).")
         |> assign_form(Editions.get_edition!(edition.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível publicar.")}
    end
  end

  def handle_event("archive", _params, socket) do
    {:ok, edition} = Editions.archive(socket.assigns.edition)
    {:noreply, socket |> put_flash(:info, "Edição arquivada.") |> assign_form(edition)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  def handle_event("remove-logo", _params, socket) do
    {:ok, edition} = Editions.update_edition(socket.assigns.edition, %{logo_path: nil})
    {:noreply, socket |> put_flash(:info, "Logo removida.") |> assign_form(edition)}
  end

  def handle_event("save_featured", %{"featured" => ids}, socket) do
    ids = List.wrap(ids)
    Editions.set_featured_merch(socket.assigns.edition.id, ids)

    {:noreply,
     socket |> put_flash(:info, "Produtos em destaque salvos.") |> assign(featured_ids: ids)}
  end

  def handle_event("save_featured", _params, socket) do
    Editions.set_featured_merch(socket.assigns.edition.id, [])
    {:noreply, socket |> put_flash(:info, "Destaques limpos.") |> assign(featured_ids: [])}
  end

  # ── data ────────────────────────────────────────────────────────────────────

  defp assign_edition(socket, _params, :new), do: assign_form(socket, %Edition{ticket_types: []})

  defp assign_edition(socket, %{"id" => id}, :edit),
    do: assign_form(socket, Editions.get_edition!(id))

  defp assign_form(socket, %Edition{} = edition) do
    socket
    |> assign(
      edition: edition,
      page_title: edition.name || "Nova edição",
      starts_at_local: starts_at_local(edition.starts_at),
      form: to_form(Editions.change_edition(edition))
    )
    |> assign_featured_merch(edition)
  end

  # Featured-merch picker só faz sentido numa edição já criada (precisa de id).
  defp assign_featured_merch(socket, %Edition{id: nil}) do
    assign(socket, all_merch: [], featured_ids: [])
  end

  defp assign_featured_merch(socket, %Edition{id: id}) do
    assign(socket,
      all_merch: Merch.list_active_items(),
      featured_ids: Editions.featured_merch_ids(id)
    )
  end

  # The datetime-local input is BRT; storage is UTC. Convert on the way in.
  defp to_utc(%{"starts_at" => v} = params) when is_binary(v) and v != "" do
    case parse_local(v) do
      {:ok, utc} -> Map.put(params, "starts_at", DateTime.to_iso8601(utc))
      :error -> params
    end
  end

  defp to_utc(params), do: params

  defp parse_local(v) do
    iso = if String.length(v) == 16, do: v <> ":00", else: v

    with {:ok, naive} <- NaiveDateTime.from_iso8601(iso),
         {:ok, dt} <- DateTime.from_naive(naive, Clock.tz()) do
      {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  defp starts_at_local(nil), do: ""

  defp starts_at_local(%DateTime{} = dt) do
    dt |> Clock.to_brt() |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp put_logo(params, socket, slug_src) do
    slug = slug_from(slug_src)

    case consume_uploaded_entries(socket, :logo, &copy_logo(slug, &1, &2)) do
      [] -> params
      [filename] -> Map.put(params, "logo_path", filename)
    end
  end

  defp copy_logo(slug, %{path: tmp}, %{client_name: name}) do
    Editions.ensure_uploads_dir!()
    ext = name |> Path.extname() |> String.downcase()
    ext = if ext in ~w(.svg .png), do: ext, else: ".png"
    filename = "edition-#{slug}-#{System.system_time(:millisecond)}#{ext}"
    File.cp!(tmp, Path.join(Editions.editions_dir(), filename))
    {:ok, filename}
  end

  defp slug_from(nil), do: "ed"

  defp slug_from(value),
    do: Regex.replace(~r/[^a-z0-9]/i, to_string(value), "") |> String.downcase()

  defp upload_error_message(:too_large), do: "Arquivo grande demais (máx 2 MB)"
  defp upload_error_message(:not_accepted), do: "Formato não aceito (use svg ou png)"
  defp upload_error_message(:too_many_files), do: "Só um arquivo"
  defp upload_error_message(other), do: to_string(other)

  defp accent(form), do: form[:accent_color].value || "#F07BC0"

  defp error_flash(changeset) do
    case changeset.errors[:ticket_types] do
      {msg, _} -> msg
      _ -> "Confira os campos abaixo."
    end
  end

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} back="Painel">
      <section class="stack-5">
        <div class="row space-between align-baseline">
          <h1 class="text-xl text-mono">
            {if @live_action == :new, do: "Nova edição", else: @edition.name}
          </h1>
          <.status_badge :if={@edition.id} status={@edition.status} />
        </div>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          id="edition-form"
          class="stack-3"
          multipart
        >
          <.input field={@form[:number]} type="number" label="Número" required inputmode="numeric" />
          <.input field={@form[:name]} label="Nome (vazio = “SESH #N”)" />

          <label class="field stack-1">
            <span class="field-label">Data e hora (horário de Brasília)</span>
            <input
              type="datetime-local"
              name="edition[starts_at]"
              value={@starts_at_local}
              class="field-input"
              required
            />
          </label>

          <.input field={@form[:venue]} label="Local" required />
          <.input field={@form[:venue_address]} label="Endereço" />
          <.input
            field={@form[:lineup]}
            type="textarea"
            label="Lineup (um nome por linha)"
            rows="4"
          />

          <div class="field stack-1">
            <span class="field-label">Cor de destaque</span>
            <div class="row gap-3 align-center">
              <input
                type="color"
                name="edition[accent_color]"
                value={accent(@form)}
                class="color-input"
              />
              <span class="text-mono text-xs">{accent(@form)}</span>
              <span
                class="swatch"
                style={"background-color:#{accent(@form)};width:1.5rem;height:1.5rem;border-radius:4px;display:inline-block"}
              >
              </span>
            </div>
          </div>

          <%!-- logo override (img, sem currentColor) --%>
          <div class="field stack-2">
            <span class="field-label">Logo da edição (opcional)</span>

            <details :if={@edition.logo_path} class="product-detail">
              <summary class="text-xs text-dim">Ver logo atual</summary>
              <div class="photo-preview mt-3">
                <img src={Editions.logo_url(@edition.logo_path)} alt="logo" width="120" />
                <button
                  type="button"
                  phx-click="remove-logo"
                  data-confirm="Remover logo atual?"
                  class="btn btn--ghost btn--sm"
                >
                  Remover
                </button>
              </div>
            </details>

            <label class="dropzone" phx-drop-target={@uploads.logo.ref}>
              <.live_file_input upload={@uploads.logo} class="dropzone-input" />
              <span class="text-xs text-muted">
                {if @edition.logo_path, do: "trocar", else: "enviar"} (svg/png, até 2 MB)
              </span>
            </label>

            <div :for={entry <- @uploads.logo.entries} class="upload-entry">
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
              <p :for={err <- upload_errors(@uploads.logo, entry)} class="field-error">
                {upload_error_message(err)}
              </p>
            </div>

            <p :for={err <- upload_errors(@uploads.logo)} class="field-error">
              {upload_error_message(err)}
            </p>
          </div>

          <%!-- lotes inline (cast_assoc + sort/drop) --%>
          <fieldset class="stack-3">
            <legend class="text-sm text-muted">Lotes</legend>

            <.inputs_for :let={lot} field={@form[:ticket_types]}>
              <div class="card stack-2">
                <input type="hidden" name="edition[ticket_types_sort][]" value={lot.index} />

                <.input field={lot[:name]} label="Nome (ex: Lote 1)" required />
                <.input
                  field={lot[:description]}
                  type="textarea"
                  label="Descrição / regras (ex: marque 2 amigos no post)"
                  rows="2"
                />
                <div class="row gap-3">
                  <.input
                    field={lot[:price_cents]}
                    type="number"
                    label="Preço (centavos)"
                    required
                    inputmode="numeric"
                  />
                  <.input
                    field={lot[:capacity]}
                    type="number"
                    label="Capacidade"
                    required
                    inputmode="numeric"
                  />
                  <.input
                    field={lot[:position]}
                    type="number"
                    label="Ordem"
                    inputmode="numeric"
                  />
                </div>
                <.input field={lot[:is_active]} type="checkbox" label="À venda" />

                <button
                  type="button"
                  name="edition[ticket_types_drop][]"
                  value={lot.index}
                  phx-click={JS.dispatch("change")}
                  class="btn btn--ghost btn--sm"
                >
                  Remover lote
                </button>
              </div>
            </.inputs_for>

            <input type="hidden" name="edition[ticket_types_drop][]" />

            <button
              type="button"
              name="edition[ticket_types_sort][]"
              value="new"
              phx-click={JS.dispatch("change")}
              class="btn btn--ghost btn--block"
            >
              + Adicionar lote
            </button>
          </fieldset>

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "Criar edição", else: "Salvar"}
          </.button>
        </.form>

        <section :if={@live_action == :edit and @all_merch != []} class="stack-3">
          <h2 class="text-sm text-muted">Produtos em destaque no /comprar</h2>
          <p class="text-xs text-dim">
            Só estes aparecem no formulário de ingresso. A loja mostra todos.
          </p>
          <form phx-submit="save_featured" class="stack-2" id="featured-merch-form">
            <label :for={item <- @all_merch} class="field field--inline">
              <input
                type="checkbox"
                name="featured[]"
                value={item.id}
                checked={item.id in @featured_ids}
                class="checkbox"
              />
              <span class="field-label">{item.name} — {money(item.price_cents)}</span>
            </label>
            <.button type="submit" variant={:ghost} class="btn--block">Salvar destaques</.button>
          </form>
        </section>

        <div :if={@edition.id} class="stack-2">
          <.button
            :if={@edition.status != :published}
            phx-click="publish"
            data-confirm="Publicar esta edição? a landing passa a mostrá-la e qualquer outra publicada é arquivada."
            class="btn--block"
          >
            Publicar
          </.button>

          <.button
            :if={@edition.status == :published}
            phx-click="archive"
            data-confirm="Despublicar? a landing volta pro teaser."
            variant={:danger}
            class="btn--block"
          >
            Despublicar
          </.button>
        </div>
      </section>
    </Layouts.admin>
    """
  end
end
