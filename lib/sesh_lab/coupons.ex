defmodule SeshLab.Coupons do
  @moduledoc """
  Coupons in two scopes:

    * `:bound`  — auto-issued by a `CouponRule` when an order reaches its
      threshold. Single-use, tied to the earning customer + device.
    * `:public` — created in admin. Multi-use up to `max_uses` (null =
      unlimited), redeemable by anyone, announced via push on creation.

  Redemption is validated read-only by `preview/2`, then claimed atomically
  inside the order transaction by `claim/3` (conditional `update_all`, same
  race-safety as stock reservation) so a coupon can't be over-spent.
  """

  import Ecto.Query

  alias SeshLab.{Clock, Notifications, Repo}
  alias SeshLab.Coupons.{Coupon, CouponRule}
  alias SeshLab.Orders.Order

  # Unambiguous alphabet (no I/L/O/0/1) for generated codes.
  @code_alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"

  # ── Rules ───────────────────────────────────────────────────────────────────

  def list_rules, do: Repo.all(from r in CouponRule, order_by: [desc: r.inserted_at])
  def list_active_rules, do: Repo.all(from r in CouponRule, where: r.is_active)
  def get_rule!(id), do: Repo.get!(CouponRule, id)
  def create_rule(attrs), do: %CouponRule{} |> CouponRule.changeset(attrs) |> Repo.insert()
  def update_rule(%CouponRule{} = r, attrs), do: r |> CouponRule.changeset(attrs) |> Repo.update()
  def delete_rule(%CouponRule{} = r), do: Repo.delete(r)
  def change_rule(%CouponRule{} = r, attrs \\ %{}), do: CouponRule.changeset(r, attrs)

  # ── Public coupons (admin) ──────────────────────────────────────────────────

  def list_coupons, do: Repo.all(from c in Coupon, order_by: [desc: c.inserted_at])

  def list_public_coupons do
    Repo.all(from c in Coupon, where: c.scope == :public, order_by: [desc: c.inserted_at])
  end

  def get_coupon!(id), do: Repo.get!(Coupon, id)

  def change_public_coupon(coupon \\ %Coupon{}, attrs \\ %{}),
    do: Coupon.public_changeset(coupon, attrs)

  @doc "Creates a public coupon and, if active, announces it to opted-in clients."
  def create_public_coupon(attrs) do
    case %Coupon{} |> Coupon.public_changeset(maybe_generate_code(attrs)) |> Repo.insert() do
      {:ok, coupon} = ok ->
        if coupon.is_active, do: Notifications.announce_coupon(coupon)
        ok

      err ->
        err
    end
  end

  def update_public_coupon(%Coupon{} = c, attrs),
    do: c |> Coupon.public_changeset(attrs) |> Repo.update()

  def delete_coupon(%Coupon{} = c), do: Repo.delete(c)

  # ── Earning (bound) ─────────────────────────────────────────────────────────

  @doc "Issues a bound coupon for each active rule the order's total satisfies."
  @spec issue_for_order(Order.t()) :: :ok
  def issue_for_order(%Order{} = order) do
    now = Clock.now_utc()

    for rule <- list_active_rules(), order.total_cents >= rule.min_order_cents do
      %{
        code: generate_code(),
        discount_kind: rule.discount_kind,
        discount_value: rule.discount_value,
        expires_at: DateTime.add(now, rule.expires_in_days * 86_400, :second),
        rule_id: rule.id,
        customer_instagram: order.customer_instagram,
        client_endpoint: order.client_endpoint,
        order_id: order.id
      }
      |> Coupon.bound_changeset()
      |> Repo.insert()
    end

    :ok
  end

  @doc "Bound coupons earned on a given order (shown on its confirmation page)."
  def earned_for_order(order_id) do
    Repo.all(from c in Coupon, where: c.order_id == ^order_id and c.scope == :bound)
  end

  @doc """
  Notifies (once) about bound coupons expiring within the next 24h. Stamps
  `notified_expiring_at` so a coupon is never re-notified. Driven hourly by
  `SeshLab.Coupons.ExpiryWorker`. `now` is injectable for tests.
  """
  @spec notify_expiring(DateTime.t()) :: :ok
  def notify_expiring(now \\ Clock.now_utc()) do
    cutoff = DateTime.add(now, 86_400, :second)

    query =
      from c in Coupon,
        where:
          c.scope == :bound and is_nil(c.used_at) and is_nil(c.notified_expiring_at) and
            not is_nil(c.client_endpoint) and not is_nil(c.expires_at) and
            c.expires_at > ^now and c.expires_at <= ^cutoff

    for coupon <- Repo.all(query) do
      coupon |> Ecto.Changeset.change(notified_expiring_at: now) |> Repo.update()
      Notifications.notify_coupon_expiring(coupon)
    end

    :ok
  end

  # ── Redemption ──────────────────────────────────────────────────────────────

  @type preview_error ::
          :not_found
          | :inactive
          | :expired
          | :used
          | :wrong_customer
          | :exhausted
          | {:min_order, pos_integer()}

  @doc """
  Read-only validation + discount calc for a code, before the order is built.
  `ctx` carries `:customer_instagram` and `:subtotal` (cents).
  """
  @spec preview(String.t() | nil, map()) ::
          {:ok, Coupon.t() | nil, non_neg_integer()} | {:error, preview_error()}
  def preview(code, %{customer_instagram: ig, subtotal: subtotal}) do
    now = Clock.now_utc()

    case get_by_code(code) do
      nil ->
        {:error, :not_found}

      %Coupon{} = c ->
        with :ok <- check_active(c),
             :ok <- check_expiry(c, now),
             :ok <- check_scope(c, ig, subtotal),
             :ok <- check_uses(c) do
          {:ok, c, Coupon.discount_cents(c, subtotal)}
        end
    end
  end

  def get_by_code(nil), do: nil
  def get_by_code(""), do: nil
  def get_by_code(code), do: Repo.get_by(Coupon, code: code |> String.trim() |> String.upcase())

  @doc """
  Atomically claims a coupon inside the order `Multi`. `:bound` flips `used_at`;
  `:public` increments `uses_count`. Returns `{:error, :coupon_taken}` if the
  guard no longer holds (already used / exhausted / expired between preview and
  commit) so the transaction rolls back.
  """
  @spec claim(Ecto.Repo.t(), Coupon.t(), Ecto.UUID.t()) ::
          {:ok, :claimed} | {:error, :coupon_taken}
  def claim(repo, %Coupon{scope: :bound, id: id}, order_id) do
    now = Clock.now_utc()

    query =
      from c in Coupon,
        where:
          c.id == ^id and c.scope == :bound and is_nil(c.used_at) and
            (is_nil(c.expires_at) or c.expires_at > ^now)

    case repo.update_all(query, set: [used_at: now, used_order_id: order_id, updated_at: now]) do
      {1, _} -> {:ok, :claimed}
      _ -> {:error, :coupon_taken}
    end
  end

  def claim(repo, %Coupon{scope: :public, id: id}, _order_id) do
    now = Clock.now_utc()

    query =
      from c in Coupon,
        where:
          c.id == ^id and c.scope == :public and c.is_active and
            (is_nil(c.expires_at) or c.expires_at > ^now) and
            (is_nil(c.max_uses) or c.uses_count < c.max_uses)

    case repo.update_all(query, inc: [uses_count: 1], set: [updated_at: now]) do
      {1, _} -> {:ok, :claimed}
      _ -> {:error, :coupon_taken}
    end
  end

  # ── Codes ───────────────────────────────────────────────────────────────────

  @doc "Generates a unique `RAD-XXXX` code."
  def generate_code do
    code = "RAD-" <> random_suffix(4)
    if Repo.exists?(from c in Coupon, where: c.code == ^code), do: generate_code(), else: code
  end

  defp maybe_generate_code(attrs) do
    case attrs["code"] || attrs[:code] do
      blank when blank in [nil, ""] -> Map.put(attrs, "code", generate_code())
      _ -> attrs
    end
  end

  defp random_suffix(n), do: for(_ <- 1..n, into: "", do: <<Enum.random(@code_alphabet)>>)

  # ── validation helpers ───────────────────────────────────────────────────────

  defp check_active(%Coupon{is_active: false}), do: {:error, :inactive}
  defp check_active(_), do: :ok

  defp check_expiry(%Coupon{expires_at: nil}, _now), do: :ok

  defp check_expiry(%Coupon{expires_at: exp}, now),
    do: if(DateTime.compare(exp, now) == :gt, do: :ok, else: {:error, :expired})

  defp check_scope(%Coupon{scope: :bound, used_at: used}, _ig, _sub) when not is_nil(used),
    do: {:error, :used}

  defp check_scope(%Coupon{scope: :bound, customer_instagram: owner}, ig, _sub),
    do: if(normalize_ig(owner) == normalize_ig(ig), do: :ok, else: {:error, :wrong_customer})

  defp check_scope(%Coupon{scope: :public, min_order_cents: min}, _ig, sub)
       when is_integer(min),
       do: if(sub >= min, do: :ok, else: {:error, {:min_order, min}})

  defp check_scope(%Coupon{scope: :public}, _ig, _sub), do: :ok

  defp check_uses(%Coupon{scope: :public, max_uses: max, uses_count: used})
       when is_integer(max),
       do: if(used < max, do: :ok, else: {:error, :exhausted})

  defp check_uses(_), do: :ok

  defp normalize_ig(nil), do: nil

  defp normalize_ig(handle),
    do: handle |> String.trim() |> String.trim_leading("@") |> String.downcase()
end
