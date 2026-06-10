defmodule SeshLabWeb.PushController do
  @moduledoc """
  Public (customer) Web Push subscription endpoints. Mirror the admin ones but
  store `audience: :client` subscriptions with opt-in `topics`.

  * `GET    /push/vapid-key`  — VAPID public key for `pushManager.subscribe`.
  * `GET    /push/subscribe`  — fetch opt-in topics for a device endpoint.
  * `POST   /push/subscribe`  — create/refresh a client subscription.
  * `PATCH  /push/subscribe`  — update opt-in topics (notification config).
  * `DELETE /push/subscribe`  — drop a subscription by endpoint.

  Goes through the CSRF-protected `:client_api` pipeline, so the browser must
  send the `x-csrf-token` header (read from the page's csrf-token meta tag).
  """

  use SeshLabWeb, :controller

  alias SeshLab.Notifications

  def vapid_key(conn, _params) do
    json(conn, %{public_key: Notifications.WebPush.Vapid.public_key()})
  end

  def show(conn, %{"endpoint" => endpoint}) when is_binary(endpoint) do
    case Notifications.get_client_topics(endpoint) do
      {:ok, topics} -> json(conn, %{topics: topics})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end

  def show(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing endpoint"})

  def subscribe(conn, %{"subscription" => sub} = params) do
    attrs = %{
      endpoint: sub["endpoint"],
      p256dh: get_in(sub, ["keys", "p256dh"]),
      auth: get_in(sub, ["keys", "auth"]),
      user_agent: params["user_agent"] || user_agent(conn),
      audience: :client,
      topics: normalize_topics(params["topics"])
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

  def update(conn, %{"endpoint" => endpoint, "topics" => topics})
      when is_binary(endpoint) and is_list(topics) do
    case Notifications.update_topics(endpoint, topics) do
      {:ok, _sub} -> json(conn, %{ok: true})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
      {:error, _cs} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid"})
    end
  end

  def update(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "bad request"})

  def unsubscribe(conn, %{"endpoint" => endpoint}) when is_binary(endpoint) do
    Notifications.unsubscribe(endpoint)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _) do
    conn |> put_status(:bad_request) |> json(%{error: "missing endpoint"})
  end

  defp normalize_topics(topics) when is_list(topics), do: topics
  defp normalize_topics(_), do: ["order_status"]

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
