defmodule SeshLabWeb.Admin.PushController do
  @moduledoc """
  Admin Web Push subscription endpoints.

  * `GET    /admin/push/vapid-key` — returns the VAPID public key so the
    browser can pass it to `pushManager.subscribe({ applicationServerKey })`.
  * `POST   /admin/push/subscribe` — persists a new (or refreshed) device
    subscription. Body shape matches `PushSubscription#toJSON()` wrapped under
    `"subscription"`.
  * `DELETE /admin/push/subscribe` — drops a subscription by endpoint.
  """

  use SeshLabWeb, :controller

  alias SeshLab.Notifications
  alias SeshLab.Notifications.WebPush.Vapid

  def vapid_key(conn, _params) do
    json(conn, %{public_key: Vapid.public_key()})
  end

  def subscribe(conn, %{"subscription" => sub} = params) do
    attrs = %{
      endpoint: sub["endpoint"],
      p256dh: get_in(sub, ["keys", "p256dh"]),
      auth: get_in(sub, ["keys", "auth"]),
      user_agent: params["user_agent"] || user_agent(conn)
    }

    case Notifications.subscribe(attrs) do
      {:ok, _sub} ->
        conn |> put_status(:created) |> json(%{ok: true})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def unsubscribe(conn, %{"endpoint" => endpoint}) when is_binary(endpoint) do
    Notifications.unsubscribe(endpoint)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _) do
    conn |> put_status(:bad_request) |> json(%{error: "missing endpoint"})
  end

  defp user_agent(conn) do
    conn |> get_req_header("user-agent") |> List.first()
  end

  defp changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
