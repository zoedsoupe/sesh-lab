defmodule SeshLab.CouponsTest do
  use SeshLab.DataCase, async: false

  import SeshLab.Fixtures, only: [edition_fixture: 0]

  alias SeshLab.{Coupons, Repo}
  alias SeshLab.Coupons.Coupon

  defp insert_order(attrs \\ %{}) do
    SeshLab.Fixtures.insert_order(edition_fixture(), attrs)
  end

  defp insert_coupon(attrs) do
    defaults = %{
      code: "SESH-TEST#{System.unique_integer([:positive])}",
      scope: :public,
      discount_kind: :percent,
      discount_value: 10,
      is_active: true,
      uses_count: 0
    }

    Repo.insert!(struct(%Coupon{}, Map.merge(defaults, attrs)))
  end

  describe "discount_cents/2" do
    test "percent rounds" do
      assert Coupon.discount_cents(%{discount_kind: :percent, discount_value: 10}, 10_000) == 1000
      assert Coupon.discount_cents(%{discount_kind: :percent, discount_value: 15}, 999) == 150
    end

    test "fixed is capped at the subtotal" do
      assert Coupon.discount_cents(%{discount_kind: :fixed, discount_value: 500}, 10_000) == 500
      assert Coupon.discount_cents(%{discount_kind: :fixed, discount_value: 99_999}, 3000) == 3000
    end
  end

  describe "generate_code/0" do
    test "produces a SESH- prefixed code with safe alphabet" do
      assert Coupons.generate_code() =~ ~r/^SESH-[A-HJ-NP-Z2-9]{4}$/
    end
  end

  describe "rules" do
    @valid_rule %{
      name: "pedido grande",
      min_order_cents: 8000,
      discount_kind: :percent,
      discount_value: 10,
      expires_in_days: 7
    }

    test "create_rule/1 inserts a valid rule" do
      assert {:ok, rule} = Coupons.create_rule(@valid_rule)
      assert rule.is_active
    end

    test "rejects a percent discount over 100" do
      assert {:error, cs} = Coupons.create_rule(%{@valid_rule | discount_value: 150})
      assert %{discount_value: _} = errors_on(cs)
    end

    test "list_active_rules/0 excludes inactive" do
      {:ok, _} = Coupons.create_rule(@valid_rule)
      {:ok, _} = Coupons.create_rule(Map.merge(@valid_rule, %{name: "off", is_active: false}))
      assert [%{name: "pedido grande"}] = Coupons.list_active_rules()
    end
  end

  describe "create_public_coupon/1" do
    test "auto-generates a code when blank" do
      assert {:ok, c} =
               Coupons.create_public_coupon(%{
                 "discount_kind" => "percent",
                 "discount_value" => "10"
               })

      assert c.code =~ ~r/^SESH-/
      assert c.scope == :public
    end

    test "keeps a custom code, upcased" do
      assert {:ok, c} =
               Coupons.create_public_coupon(%{
                 "code" => "blackfriday10",
                 "discount_kind" => "percent",
                 "discount_value" => "10"
               })

      assert c.code == "BLACKFRIDAY10"
    end
  end

  describe "issue_for_order/1" do
    setup do
      {:ok, rule} =
        Coupons.create_rule(%{
          name: "premia",
          min_order_cents: 8000,
          discount_kind: :percent,
          discount_value: 10,
          expires_in_days: 7
        })

      {:ok, rule: rule}
    end

    test "issues a bound coupon when the total meets the threshold", %{rule: rule} do
      order = insert_order(%{total_cents: 9000, customer_instagram: "fulano"})
      assert :ok = Coupons.issue_for_order(order)

      assert [coupon] = Coupons.earned_for_order(order.id)
      assert coupon.scope == :bound
      assert coupon.customer_instagram == "fulano"
      assert coupon.discount_kind == rule.discount_kind
      assert coupon.expires_at
    end

    test "issues nothing below the threshold" do
      order = insert_order(%{total_cents: 5000})
      assert :ok = Coupons.issue_for_order(order)
      assert Coupons.earned_for_order(order.id) == []
    end
  end

  describe "preview/2" do
    test "returns not_found for an unknown code" do
      assert {:error, :not_found} =
               Coupons.preview("NOPE", %{customer_instagram: "x", subtotal: 1000})
    end

    test "computes discount for a valid public coupon" do
      insert_coupon(%{code: "PUB10", discount_kind: :percent, discount_value: 10})

      assert {:ok, %Coupon{code: "PUB10"}, 1000} =
               Coupons.preview("PUB10", %{customer_instagram: "x", subtotal: 10_000})
    end

    test "enforces public min_order" do
      insert_coupon(%{code: "MIN50", min_order_cents: 5000})

      assert {:error, {:min_order, 5000}} =
               Coupons.preview("MIN50", %{customer_instagram: "x", subtotal: 3000})
    end

    test "rejects an exhausted public coupon" do
      insert_coupon(%{code: "ONE", max_uses: 1, uses_count: 1})

      assert {:error, :exhausted} =
               Coupons.preview("ONE", %{customer_instagram: "x", subtotal: 1000})
    end

    test "rejects an expired coupon" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      insert_coupon(%{code: "OLD", expires_at: past})

      assert {:error, :expired} =
               Coupons.preview("OLD", %{customer_instagram: "x", subtotal: 1000})
    end

    test "bound coupon requires the same customer" do
      insert_coupon(%{code: "MINE", scope: :bound, customer_instagram: "alice"})

      assert {:error, :wrong_customer} =
               Coupons.preview("MINE", %{customer_instagram: "bob", subtotal: 1000})

      assert {:ok, _, _} =
               Coupons.preview("MINE", %{customer_instagram: "@Alice", subtotal: 1000})
    end

    test "bound coupon already used is rejected" do
      used = DateTime.utc_now() |> DateTime.truncate(:second)
      insert_coupon(%{code: "DONE", scope: :bound, customer_instagram: "alice", used_at: used})

      assert {:error, :used} =
               Coupons.preview("DONE", %{customer_instagram: "alice", subtotal: 1000})
    end
  end

  describe "claim/3" do
    test "bound coupon can only be claimed once" do
      order = insert_order()
      coupon = insert_coupon(%{code: "B1", scope: :bound, customer_instagram: "diana"})

      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:error, :coupon_taken} = Coupons.claim(Repo, coupon, order.id)

      assert Repo.get(Coupon, coupon.id).used_at
    end

    test "public coupon increments uses up to its cap" do
      order = insert_order()
      coupon = insert_coupon(%{code: "P1", scope: :public, max_uses: 2, uses_count: 0})

      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:error, :coupon_taken} = Coupons.claim(Repo, coupon, order.id)

      assert Repo.get(Coupon, coupon.id).uses_count == 2
    end
  end

  describe "notify_expiring/1" do
    setup do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, now: now, soon: DateTime.add(now, 3600, :second)}
    end

    test "marks bound coupons expiring within 24h, skips later ones", %{now: now, soon: soon} do
      later = DateTime.add(now, 3 * 86_400, :second)

      c_soon =
        insert_coupon(%{
          code: "SOON",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/x",
          expires_at: soon
        })

      c_later =
        insert_coupon(%{
          code: "LATER",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/y",
          expires_at: later
        })

      assert :ok = Coupons.notify_expiring(now)
      assert Repo.get(Coupon, c_soon.id).notified_expiring_at
      refute Repo.get(Coupon, c_later.id).notified_expiring_at
    end

    test "skips coupons without a device", %{now: now, soon: soon} do
      c =
        insert_coupon(%{
          code: "NODEV",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: nil,
          expires_at: soon
        })

      assert :ok = Coupons.notify_expiring(now)
      refute Repo.get(Coupon, c.id).notified_expiring_at
    end

    test "skips already-used coupons", %{now: now, soon: soon} do
      c =
        insert_coupon(%{
          code: "USED",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/u",
          expires_at: soon,
          used_at: now
        })

      assert :ok = Coupons.notify_expiring(now)
      refute Repo.get(Coupon, c.id).notified_expiring_at
    end

    test "is idempotent across ticks", %{now: now, soon: soon} do
      c =
        insert_coupon(%{
          code: "ONCE",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/z",
          expires_at: soon
        })

      Coupons.notify_expiring(now)
      first = Repo.get(Coupon, c.id).notified_expiring_at
      assert first

      Coupons.notify_expiring(DateTime.add(now, 60, :second))
      assert Repo.get(Coupon, c.id).notified_expiring_at == first
    end
  end
end
