defmodule SeshLab.Notifications do
  @moduledoc """
  Public API for admin Web Push notifications.

  Stores push subscriptions, fans out notifications across all registered
  devices in unlinked tasks (so order creation latency isn't affected by push
  service round-trips), and prunes subscriptions the push service reports as
  gone (HTTP 404/410).
  """

  import Ecto.Query
  require Logger

  alias SeshLab.{Clock, Repo}
  alias SeshLab.Editions.{Edition, TicketType}
  alias SeshLab.Tickets.Order
  alias SeshLab.Notifications.{PushSubscription, WebPush}

  # ── Subscriptions ──────────────────────────────────────────────────────────

  @spec subscribe(map()) :: {:ok, PushSubscription.t()} | {:error, Ecto.Changeset.t()}
  def subscribe(attrs) do
    %PushSubscription{}
    |> PushSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :user_agent, :audience, :topics, :updated_at]},
      conflict_target: :endpoint,
      returning: true
    )
  end

  @spec unsubscribe(endpoint :: String.t()) :: :ok
  def unsubscribe(endpoint) do
    PushSubscription
    |> where(endpoint: ^endpoint)
    |> Repo.delete_all()

    :ok
  end

  @doc "Returns the opt-in topics for a client subscription by endpoint."
  @spec get_client_topics(endpoint :: String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def get_client_topics(endpoint) do
    case Repo.get_by(PushSubscription, endpoint: endpoint, audience: :client) do
      nil -> {:error, :not_found}
      %PushSubscription{topics: topics} -> {:ok, topics || []}
    end
  end

  @doc "Updates the opt-in topics of a client subscription (config panel)."
  @spec update_topics(endpoint :: String.t(), [String.t()]) ::
          {:ok, PushSubscription.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_topics(endpoint, topics) when is_list(topics) do
    case Repo.get_by(PushSubscription, endpoint: endpoint, audience: :client) do
      nil -> {:error, :not_found}
      sub -> sub |> PushSubscription.changeset(%{topics: topics}) |> Repo.update()
    end
  end

  @spec list_subscriptions(audience :: :admin | :client | nil) :: [PushSubscription.t()]
  def list_subscriptions(audience \\ nil) do
    PushSubscription
    |> filter_audience(audience)
    |> Repo.all()
  end

  defp filter_audience(query, nil), do: query
  defp filter_audience(query, audience), do: where(query, audience: ^audience)

  @spec subscription_count() :: non_neg_integer()
  def subscription_count, do: Repo.aggregate(PushSubscription, :count, :id)

  # ── Admin notifications ────────────────────────────────────────────────────

  @spec notify_admin_new_order(Order.t()) :: :ok
  def notify_admin_new_order(%Order{} = order) do
    order = preload_items(order)

    payload = %{
      "t" => "new_order",
      "id" => order.id,
      "n" => first_name(order.customer_name),
      "v" => format_money(order.total_cents),
      "q" => Enum.sum(Enum.map(order.items || [], & &1.quantity)),
      "url" => "/admin/pedidos/#{order.id}"
    }

    fanout(payload, audience: :admin, urgency: "high", topic: "order-" <> short_id(order.id))
  end

  @spec notify_admin_soldout(TicketType.t()) :: :ok
  def notify_admin_soldout(%TicketType{} = type) do
    payload = %{
      "t" => "soldout",
      "name" => type.name,
      "url" => "/admin"
    }

    fanout(payload, audience: :admin, urgency: "normal", topic: "soldout-" <> short_id(type.id))
  end

  @spec notify_admin_dj_application(%{name: String.t()}) :: :ok
  def notify_admin_dj_application(%{name: name}) do
    payload = %{
      "t" => "dj_application",
      "n" => first_name(name),
      "url" => "/admin/tocar"
    }

    fanout(payload, audience: :admin, urgency: "normal")
  end

  # ── Customer notifications ─────────────────────────────────────────────────

  @doc """
  Pushes a status update to the device that placed `order` (if it subscribed
  and opted into `order_status`). No-op when the order has no linked device.
  """
  @spec notify_customer_order_update(Order.t()) :: :ok
  def notify_customer_order_update(%Order{client_endpoint: endpoint, status: status} = order)
      when is_binary(endpoint) do
    with %PushSubscription{topics: topics} = sub <-
           Repo.get_by(PushSubscription, endpoint: endpoint, audience: :client),
         true <- "order_status" in (topics || []) do
      payload = %{
        "t" => "order_status",
        "id" => order.id,
        "s" => to_string(status),
        "url" => "/compra/#{order.id}"
      }

      Task.start(fn ->
        push_one(sub, payload, urgency: "high", topic: "status-" <> short_id(order.id))
      end)
    end

    :ok
  end

  def notify_customer_order_update(_), do: :ok

  @doc """
  Pushes a "your coupon expires tomorrow" notice to the coupon's device, if it
  subscribed and opted into `coupons`. No-op otherwise.
  """
  @spec notify_coupon_expiring(%{client_endpoint: String.t() | nil, code: String.t()}) :: :ok
  def notify_coupon_expiring(%{client_endpoint: endpoint, code: code}) when is_binary(endpoint) do
    with %PushSubscription{topics: topics} = sub <-
           Repo.get_by(PushSubscription, endpoint: endpoint, audience: :client),
         true <- "coupons" in (topics || []) do
      payload = %{"t" => "coupon_expiring", "code" => code, "url" => "/"}
      Task.start(fn -> push_one(sub, payload, urgency: "normal", topic: "coupon-#{code}") end)
    end

    :ok
  end

  def notify_coupon_expiring(_), do: :ok

  @doc "Anuncia uma edição recém-publicada a todo cliente opt-in em `editions`."
  @spec announce_edition(Edition.t()) :: :ok
  def announce_edition(%Edition{} = edition) do
    broadcast_to_topic("editions", %{
      "t" => "edition",
      "title" => "#{edition.name} anunciada",
      "body" => "#{Clock.format(edition.starts_at, :date)} — #{edition.venue}",
      "url" => "/"
    })
  end

  @doc "Announces a newly-created public coupon to every `coupons`-opted client."
  @spec announce_coupon(%{
          code: String.t(),
          discount_kind: atom(),
          discount_value: integer(),
          expires_at: DateTime.t() | nil
        }) :: :ok
  def announce_coupon(%{code: code, discount_kind: kind, discount_value: value, expires_at: exp}) do
    body = "use #{code} — #{discount_label(kind, value)}#{expiry_suffix(exp)}"

    broadcast_to_topic("coupons", %{
      "t" => "coupon",
      "title" => "novo cupom",
      "body" => body,
      "url" => "/"
    })
  end

  defp broadcast_to_topic(topic, payload) do
    :client
    |> list_subscriptions()
    |> Enum.filter(&(topic in (&1.topics || [])))
    |> Enum.each(fn sub -> Task.start(fn -> push_one(sub, payload, urgency: "low") end) end)

    :ok
  end

  defp discount_label(:percent, value), do: "#{value}% off"
  defp discount_label(:fixed, value), do: "R$ #{format_money(value)} off"

  defp expiry_suffix(nil), do: ""
  defp expiry_suffix(%DateTime{} = exp), do: " até #{Clock.format(exp, :date)}"

  # ── internals ──────────────────────────────────────────────────────────────

  defp fanout(payload, opts) do
    {audience, push_opts} = Keyword.pop!(opts, :audience)

    case list_subscriptions(audience) do
      [] ->
        Logger.debug("[notifications] no #{audience} subscriptions, skipping #{payload["t"]}")
        :ok

      subs ->
        Enum.each(subs, fn sub ->
          Task.start(fn -> push_one(sub, payload, push_opts) end)
        end)

        :ok
    end
  end

  defp push_one(sub, payload, opts) do
    case WebPush.send(sub, payload, opts) do
      :ok -> :ok
      {:error, :gone} -> unsubscribe(sub.endpoint)
      {:error, _reason} -> :ok
    end
  end

  defp preload_items(%Order{items: %Ecto.Association.NotLoaded{}} = o),
    do: Repo.preload(o, :items)

  defp preload_items(o), do: o

  defp first_name(nil), do: ""

  defp first_name(name) do
    name |> String.split(~r/\s+/, parts: 2) |> List.first()
  end

  defp format_money(cents) when is_integer(cents) do
    (cents / 100)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
  end

  defp format_money(_), do: ""

  # Topic must be URL-safe ≤ 32 chars; UUIDs are 36 so we shorten.
  defp short_id(id), do: id |> String.replace("-", "") |> binary_part(0, 16)
end
