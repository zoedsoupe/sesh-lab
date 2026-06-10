defmodule SeshLab.NotificationsTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.Notifications
  alias SeshLab.Notifications.PushSubscription

  @valid_attrs %{
    endpoint: "https://fcm.googleapis.com/fcm/send/abc",
    p256dh:
      "BAhAOIWaG6vmEZyJ-LqDJOlT5_NgkY-7-VG3R5w7vJlYxX2g2WMl2pK0d8sHJ0DqfYxOJrlGZ0xPpQwR3sTOAqs",
    auth: "tBHIt7O_aSIgg"
  }

  describe "subscribe/1" do
    test "inserts a new subscription" do
      assert {:ok, %PushSubscription{} = sub} = Notifications.subscribe(@valid_attrs)
      assert sub.endpoint == @valid_attrs.endpoint
      assert sub.p256dh == @valid_attrs.p256dh
      assert sub.auth == @valid_attrs.auth
      assert Notifications.subscription_count() == 1
    end

    test "re-subscribing same endpoint updates keys instead of inserting" do
      {:ok, _} = Notifications.subscribe(@valid_attrs)

      updated =
        Map.merge(@valid_attrs, %{
          p256dh: "BNEWKEY_replacing_the_previous_one_with_a_fresh_p256dh_value",
          auth: "newauthvalue"
        })

      assert {:ok, _} = Notifications.subscribe(updated)
      assert Notifications.subscription_count() == 1

      [sub] = Notifications.list_subscriptions()
      assert sub.p256dh == updated.p256dh
      assert sub.auth == updated.auth
    end

    test "captures optional user_agent" do
      attrs = Map.put(@valid_attrs, :user_agent, "Mozilla/5.0 (Android)")
      assert {:ok, sub} = Notifications.subscribe(attrs)
      assert sub.user_agent == "Mozilla/5.0 (Android)"
    end

    test "rejects missing required keys" do
      assert {:error, cs} = Notifications.subscribe(%{endpoint: "x"})
      errors = errors_on(cs)
      assert "can't be blank" in errors.p256dh
      assert "can't be blank" in errors.auth
    end
  end

  describe "unsubscribe/1" do
    test "deletes by endpoint" do
      {:ok, _} = Notifications.subscribe(@valid_attrs)
      assert :ok = Notifications.unsubscribe(@valid_attrs.endpoint)
      assert Notifications.subscription_count() == 0
    end

    test "is idempotent when the endpoint is unknown" do
      assert :ok = Notifications.unsubscribe("https://no.such.endpoint/foo")
    end
  end

  describe "list_subscriptions/0" do
    test "returns all stored subscriptions" do
      attrs2 = %{@valid_attrs | endpoint: "https://fcm.googleapis.com/fcm/send/zzz"}

      {:ok, _} = Notifications.subscribe(@valid_attrs)
      {:ok, _} = Notifications.subscribe(attrs2)

      endpoints =
        Notifications.list_subscriptions()
        |> Enum.map(& &1.endpoint)
        |> Enum.sort()

      assert endpoints == Enum.sort([@valid_attrs.endpoint, attrs2.endpoint])
    end
  end

  describe "notify_admin_*/_" do
    test "is a no-op when there are no subscriptions" do
      order = %SeshLab.Orders.Order{
        id: "00000000-0000-0000-0000-000000000001",
        customer_name: "Fulano",
        total_cents: 1500,
        items: []
      }

      assert :ok = Notifications.notify_admin_new_order(order)
      assert :ok = Notifications.notify_admin_out_of_stock("brownie", "Brownie")
    end
  end

  describe "client subscriptions" do
    setup do
      client =
        @valid_attrs
        |> Map.merge(%{audience: :client, topics: ["order_status"]})

      {:ok, client_attrs: client}
    end

    test "subscribe/1 stores audience and topics", %{client_attrs: attrs} do
      assert {:ok, sub} = Notifications.subscribe(attrs)
      assert sub.audience == :client
      assert sub.topics == ["order_status"]
    end

    test "rejects unknown topics", %{client_attrs: attrs} do
      assert {:error, cs} = Notifications.subscribe(%{attrs | topics: ["bogus"]})
      assert %{topics: _} = errors_on(cs)
    end

    test "list_subscriptions/1 filters by audience", %{client_attrs: client} do
      admin = %{@valid_attrs | endpoint: "https://fcm.googleapis.com/fcm/send/admin"}

      {:ok, _} = Notifications.subscribe(admin)
      {:ok, _} = Notifications.subscribe(client)

      assert [a] = Notifications.list_subscriptions(:admin)
      assert a.audience == :admin
      assert [c] = Notifications.list_subscriptions(:client)
      assert c.audience == :client
      assert length(Notifications.list_subscriptions()) == 2
    end

    test "update_topics/2 changes a client sub's topics", %{client_attrs: attrs} do
      {:ok, _} = Notifications.subscribe(attrs)

      assert {:ok, sub} =
               Notifications.update_topics(attrs.endpoint, ["order_status", "promos"])

      assert Enum.sort(sub.topics) == ["order_status", "promos"]
    end

    test "update_topics/2 returns :not_found for unknown or admin endpoints", %{
      client_attrs: client
    } do
      {:ok, _} = Notifications.subscribe(Map.put(@valid_attrs, :audience, :admin))

      assert {:error, :not_found} = Notifications.update_topics("https://nope/x", ["promos"])
      # endpoint exists but is an admin sub — not addressable as a client
      assert {:error, :not_found} = Notifications.update_topics(client.endpoint, ["promos"])
    end
  end

  describe "notify_customer_order_update/1" do
    alias SeshLab.Orders.Order

    test "no-ops when the order has no linked device" do
      assert :ok = Notifications.notify_customer_order_update(%Order{client_endpoint: nil})
    end

    test "no-ops when no client subscription matches the endpoint" do
      order = %Order{
        id: "00000000-0000-0000-0000-000000000002",
        client_endpoint: "https://fcm.googleapis.com/fcm/send/ghost",
        status: :confirmed
      }

      assert :ok = Notifications.notify_customer_order_update(order)
    end

    test "no-ops when the device opted out of order_status" do
      attrs = Map.merge(@valid_attrs, %{audience: :client, topics: ["promos"]})
      {:ok, _} = Notifications.subscribe(attrs)

      order = %Order{
        id: "00000000-0000-0000-0000-000000000003",
        client_endpoint: attrs.endpoint,
        status: :confirmed
      }

      assert :ok = Notifications.notify_customer_order_update(order)
    end
  end

  describe "notify_clients_promo/2" do
    test "is a no-op when no device opted into promos" do
      assert :ok = Notifications.notify_clients_promo("Cupom", "10% off")
    end
  end

  describe "notify_coupon_expiring/1" do
    test "no-op without a matching client subscription" do
      assert :ok =
               Notifications.notify_coupon_expiring(%{
                 client_endpoint: "https://fcm.googleapis.com/fcm/send/ghost",
                 code: "X"
               })
    end

    test "no-op when the device did not opt into coupons" do
      attrs = Map.merge(@valid_attrs, %{audience: :client, topics: ["order_status"]})
      {:ok, _} = Notifications.subscribe(attrs)

      assert :ok =
               Notifications.notify_coupon_expiring(%{
                 client_endpoint: @valid_attrs.endpoint,
                 code: "X"
               })
    end

    test "no-op for a coupon without a device" do
      assert :ok = Notifications.notify_coupon_expiring(%{client_endpoint: nil, code: "X"})
    end
  end

  describe "announce_promo/1" do
    test "accepts coupons as a valid topic" do
      attrs = Map.merge(@valid_attrs, %{audience: :client, topics: ["promos", "coupons"]})
      assert {:ok, sub} = Notifications.subscribe(attrs)
      assert Enum.sort(sub.topics) == ["coupons", "promos"]
    end

    test "is a no-op when no device opted into promos" do
      assert :ok = Notifications.announce_promo(%{name: "Combo Festa", total_cents: 8000})
    end
  end
end
