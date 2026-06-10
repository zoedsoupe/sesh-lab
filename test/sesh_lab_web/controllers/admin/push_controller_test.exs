defmodule SeshLabWeb.Admin.PushControllerTest do
  use SeshLabWeb.ConnCase, async: false

  alias SeshLab.Notifications

  @subscription %{
    "endpoint" => "https://fcm.googleapis.com/fcm/send/abc123",
    "keys" => %{
      "p256dh" =>
        "BAhAOIWaG6vmEZyJ-LqDJOlT5_NgkY-7-VG3R5w7vJlYxX2g2WMl2pK0d8sHJ0DqfYxOJrlGZ0xPpQwR3sTOAqs",
      "auth" => "tBHIt7O_aSIgg"
    }
  }

  setup do
    cfg = Application.fetch_env!(:sesh_lab, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")

    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    pub_b64 = Base.url_encode64(pub, padding: false)
    priv_b64 = Base.url_encode64(priv, padding: false)

    prev_vapid = Application.get_env(:sesh_lab, :vapid)

    Application.put_env(:sesh_lab, :vapid,
      public_key: pub_b64,
      private_key: priv_b64,
      subject: "mailto:test@example.com"
    )

    on_exit(fn ->
      if prev_vapid,
        do: Application.put_env(:sesh_lab, :vapid, prev_vapid),
        else: Application.delete_env(:sesh_lab, :vapid)
    end)

    %{auth_header: auth, public_key_b64: pub_b64}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  describe "without authentication" do
    test "returns 401 on vapid-key", %{conn: conn} do
      conn = get(conn, ~p"/admin/push/vapid-key")
      assert conn.status == 401
    end

    test "returns 401 on subscribe", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/admin/push/subscribe", Jason.encode!(%{subscription: @subscription}))

      assert conn.status == 401
    end
  end

  describe "GET /admin/push/vapid-key" do
    test "returns the configured public key", %{conn: conn, auth_header: auth, public_key_b64: pk} do
      conn = conn |> authed(auth) |> get(~p"/admin/push/vapid-key")
      assert %{"public_key" => ^pk} = json_response(conn, 200)
    end
  end

  describe "POST /admin/push/subscribe" do
    test "persists a new subscription", %{conn: conn, auth_header: auth} do
      body = Jason.encode!(%{subscription: @subscription, user_agent: "Test/1.0"})

      conn =
        conn
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/admin/push/subscribe", body)

      assert %{"ok" => true} = json_response(conn, 201)
      assert Notifications.subscription_count() == 1

      [sub] = Notifications.list_subscriptions()
      assert sub.endpoint == @subscription["endpoint"]
      assert sub.p256dh == @subscription["keys"]["p256dh"]
      assert sub.auth == @subscription["keys"]["auth"]
      assert sub.user_agent == "Test/1.0"
    end

    test "is idempotent (same endpoint replaces keys)", %{conn: conn, auth_header: auth} do
      body1 = Jason.encode!(%{subscription: @subscription})

      conn
      |> authed(auth)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/admin/push/subscribe", body1)

      new_sub =
        put_in(@subscription, ["keys", "p256dh"], "BNEW_REPLACEMENT_KEY_____________value")

      body2 = Jason.encode!(%{subscription: new_sub})

      conn =
        build_conn()
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/admin/push/subscribe", body2)

      assert %{"ok" => true} = json_response(conn, 201)
      assert Notifications.subscription_count() == 1
    end

    test "returns 422 on missing required keys", %{conn: conn, auth_header: auth} do
      body =
        Jason.encode!(%{
          subscription: %{"endpoint" => "https://example.com/foo", "keys" => %{}}
        })

      conn =
        conn
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/admin/push/subscribe", body)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["p256dh"] == ["can't be blank"]
      assert errors["auth"] == ["can't be blank"]
    end
  end

  describe "DELETE /admin/push/subscribe" do
    test "removes the subscription matching the endpoint", %{conn: conn, auth_header: auth} do
      {:ok, _} =
        Notifications.subscribe(%{
          endpoint: @subscription["endpoint"],
          p256dh: @subscription["keys"]["p256dh"],
          auth: @subscription["keys"]["auth"]
        })

      conn =
        conn
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> delete(
          ~p"/admin/push/subscribe",
          Jason.encode!(%{endpoint: @subscription["endpoint"]})
        )

      assert %{"ok" => true} = json_response(conn, 200)
      assert Notifications.subscription_count() == 0
    end

    test "is idempotent when the endpoint is unknown", %{conn: conn, auth_header: auth} do
      conn =
        conn
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/admin/push/subscribe", Jason.encode!(%{endpoint: "missing"}))

      assert %{"ok" => true} = json_response(conn, 200)
    end

    test "returns 400 when endpoint is missing from the body", %{conn: conn, auth_header: auth} do
      conn =
        conn
        |> authed(auth)
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/admin/push/subscribe", Jason.encode!(%{}))

      assert json_response(conn, 400)
    end
  end
end
