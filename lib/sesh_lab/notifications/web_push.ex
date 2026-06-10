defmodule SeshLab.Notifications.WebPush do
  @moduledoc """
  Top-level Web Push sender.

  Encrypts a JSON payload with `aes128gcm` (`WebPush.Encryption`) and signs a
  VAPID JWT (`WebPush.Vapid`), then POSTs the resulting binary body to the
  subscription's push service endpoint via Finch.

  Returns:
    * `:ok` — push service accepted (HTTP 200/201/202/204)
    * `{:error, :gone}` — subscription no longer valid (404/410); the caller
      should delete the row from `push_subscriptions`
    * `{:error, term}` — transport or unexpected status; logged + surfaced
  """

  require Logger

  alias SeshLab.Notifications.PushSubscription
  alias SeshLab.Notifications.WebPush.{Encryption, Vapid}

  @default_ttl 86_400
  @finch_name SeshLab.WebPush.Finch

  @type send_result :: :ok | {:error, :gone} | {:error, term()}

  @doc """
  Send `payload` (JSON-encoded with `Jason`) to `subscription`.

  ## Options

    * `:ttl` — seconds the push service may hold the message (default 86400)
    * `:urgency` — `"very-low" | "low" | "normal" | "high"` (default `"normal"`)
    * `:topic` — URL-safe string ≤ 32 chars; lets the push service collapse
      pending messages with the same topic into the latest one
  """
  @spec send(PushSubscription.t(), map(), keyword()) :: send_result()
  def send(%PushSubscription{} = sub, payload, opts \\ []) when is_map(payload) do
    body = Jason.encode!(payload)
    encrypted = Encryption.encrypt(body, sub.p256dh, sub.auth)
    headers = build_headers(sub.endpoint, opts)

    req = Finch.build(:post, sub.endpoint, headers, encrypted)

    case Finch.request(req, @finch_name) do
      {:ok, %{status: status}} when status in [200, 201, 202, 204] ->
        :ok

      {:ok, %{status: status}} when status in [404, 410] ->
        Logger.info("[web_push] subscription gone (#{status})")
        {:error, :gone}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[web_push] push failed #{status}: #{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[web_push] transport failure: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_headers(endpoint, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    urgency = Keyword.get(opts, :urgency, "normal")
    topic = Keyword.get(opts, :topic)

    base = [
      {"authorization", Vapid.authorization_header(endpoint)},
      {"content-type", "application/octet-stream"},
      {"content-encoding", "aes128gcm"},
      {"ttl", Integer.to_string(ttl)},
      {"urgency", urgency}
    ]

    if topic, do: [{"topic", topic} | base], else: base
  end
end
