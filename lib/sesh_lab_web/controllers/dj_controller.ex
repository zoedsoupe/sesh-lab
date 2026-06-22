defmodule SeshLabWeb.DjController do
  use SeshLabWeb, :controller

  alias SeshLab.DjApplications
  alias SeshLab.DjApplications.DjApplication

  # Tempo mínimo (s) entre carregar o form e enviar. Humano não preenche
  # 5 campos em < 3s; bot que faz POST direto não espera.
  @min_fill_seconds 3
  @ts_salt "dj_form"

  def new(conn, params) do
    render(conn, :new,
      changeset: DjApplications.change(%DjApplication{}),
      submitted: params["ok"] == "1",
      form_ts: sign_ts(conn),
      open?: SeshLab.Settings.dj_applications_open?(),
      page_title: "Quer tocar?"
    )
  end

  def create(conn, params) do
    cond do
      # ponytail: silent_ok com inscrições fechadas significa que um humano que
      # tinha o form aberto quando fechou recebe um sucesso falso — aceitável
      # (revisão manual, nada persiste); troca por flash + re-render se importar.
      not SeshLab.Settings.dj_applications_open?() -> silent_ok(conn)
      # Honeypot: campo "site" escondido; bot preenche, humano não.
      honeypot_filled?(params) -> silent_ok(conn)
      # Timestamp assinado: rejeita POST instantâneo (bot) sem dar pista.
      not human_paced?(conn, params["ts"]) -> silent_ok(conn)
      true -> persist(conn, Map.get(params, "dj_application", %{}))
    end
  end

  defp persist(conn, attrs) do
    case DjApplications.create(attrs) do
      {:ok, _application} ->
        redirect(conn, to: ~p"/tocar?ok=1")

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_flash(:error, "Confere os campos e tenta de novo.")
        |> render(:new,
          changeset: %{cs | action: :insert},
          submitted: false,
          form_ts: sign_ts(conn),
          open?: SeshLab.Settings.dj_applications_open?(),
          page_title: "Quer tocar?"
        )
    end
  end

  # Sucesso silencioso: bot acha que passou, nada persiste.
  defp silent_ok(conn), do: redirect(conn, to: ~p"/tocar?ok=1")

  defp honeypot_filled?(params) do
    case params["site"] do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp sign_ts(conn), do: Phoenix.Token.sign(conn, @ts_salt, System.system_time(:second))

  defp human_paced?(conn, ts) when is_binary(ts) do
    case Phoenix.Token.verify(conn, @ts_salt, ts, max_age: 3600) do
      {:ok, signed_at} -> System.system_time(:second) - signed_at >= @min_fill_seconds
      _ -> false
    end
  end

  defp human_paced?(_conn, _ts), do: false
end
