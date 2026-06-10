defmodule SeshLab.Notifications.WebPush.VapidTest do
  use ExUnit.Case, async: false

  alias SeshLab.Notifications.WebPush.Vapid

  setup do
    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    pub_b64 = Base.url_encode64(pub, padding: false)
    priv_b64 = Base.url_encode64(priv, padding: false)

    prev = Application.get_env(:sesh_lab, :vapid)

    Application.put_env(:sesh_lab, :vapid,
      public_key: pub_b64,
      private_key: priv_b64,
      subject: "mailto:test@example.com"
    )

    on_exit(fn ->
      if prev,
        do: Application.put_env(:sesh_lab, :vapid, prev),
        else: Application.delete_env(:sesh_lab, :vapid)
    end)

    %{public_key: pub, public_key_b64: pub_b64}
  end

  describe "authorization_header/1" do
    test "produces a JWT verifiable with the configured public key", %{
      public_key: pub,
      public_key_b64: pub_b64
    } do
      endpoint = "https://fcm.googleapis.com/fcm/send/abc"
      header = Vapid.authorization_header(endpoint)

      assert "vapid t=" <> rest = header
      [jwt, "k=" <> key_part] = String.split(rest, ", ")
      assert key_part == pub_b64

      [h_b64, c_b64, s_b64] = String.split(jwt, ".")
      header_map = Jason.decode!(b64d(h_b64))
      claims = Jason.decode!(b64d(c_b64))
      sig_raw = b64d(s_b64)

      assert header_map == %{"typ" => "JWT", "alg" => "ES256"}
      assert byte_size(sig_raw) == 64

      now = System.system_time(:second)
      assert claims["aud"] == "https://fcm.googleapis.com"
      assert claims["sub"] == "mailto:test@example.com"
      assert claims["exp"] > now
      assert claims["exp"] <= now + 12 * 3600

      signing_input = h_b64 <> "." <> c_b64
      der_sig = raw_to_der(sig_raw)
      assert :crypto.verify(:ecdsa, :sha256, signing_input, der_sig, [pub, :secp256r1])
    end

    test "audience matches the endpoint's origin (host + scheme + non-default port)" do
      header1 = Vapid.authorization_header("https://fcm.googleapis.com/fcm/send/xyz")
      [_, claims1, _] = parse_jwt(header1)
      assert claims1["aud"] == "https://fcm.googleapis.com"

      header2 = Vapid.authorization_header("http://localhost:4000/push/foo")
      [_, claims2, _] = parse_jwt(header2)
      assert claims2["aud"] == "http://localhost:4000"
    end
  end

  describe "audience_for/1" do
    test "strips path and default ports" do
      assert Vapid.audience_for("https://fcm.googleapis.com/fcm/send/abc") ==
               "https://fcm.googleapis.com"

      assert Vapid.audience_for("https://example.com:443/foo") == "https://example.com"
      assert Vapid.audience_for("http://example.com:80/bar") == "http://example.com"
      assert Vapid.audience_for("http://localhost:4000/baz") == "http://localhost:4000"
    end
  end

  describe "public_key/0" do
    test "returns the configured base64 public key", %{public_key_b64: pub_b64} do
      assert Vapid.public_key() == pub_b64
    end
  end

  defp parse_jwt("vapid t=" <> rest) do
    [jwt, _] = String.split(rest, ", ")
    [h, c, s] = String.split(jwt, ".")
    [Jason.decode!(b64d(h)), Jason.decode!(b64d(c)), b64d(s)]
  end

  defp b64d(s), do: Base.url_decode64!(s, padding: false)

  # Convert JWS-style raw 64-byte ECDSA signature back to DER for :crypto.verify.
  defp raw_to_der(<<r::binary-size(32), s::binary-size(32)>>) do
    inner = der_int(r) <> der_int(s)
    <<0x30, byte_size(inner)>> <> inner
  end

  defp der_int(bin) do
    trimmed = trim_leading_zero(bin)

    body =
      if :binary.first(trimmed) >= 0x80,
        do: <<0>> <> trimmed,
        else: trimmed

    <<0x02, byte_size(body)>> <> body
  end

  defp trim_leading_zero(<<0, rest::binary>>) when byte_size(rest) > 0,
    do: trim_leading_zero(rest)

  defp trim_leading_zero(b), do: b
end
