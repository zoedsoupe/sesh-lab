defmodule SeshLab.Notifications.WebPush.Vapid do
  @moduledoc """
  VAPID (RFC 8292) JWT signing for Web Push authentication.

  Build a JWT with `ES256` over the claims `{aud, exp, sub}`, sign it with
  the VAPID P-256 private key, and return the `Authorization` header value
  in the form `vapid t=<jwt>, k=<vapid_public_b64>`.
  """

  @alg "ES256"
  @typ "JWT"
  # Spec allows up to 24h; we use 12h to give some slack between sign and send.
  @exp_seconds 12 * 3600

  @doc """
  Build the full `Authorization` header value for a request to `endpoint_url`.
  """
  @spec authorization_header(String.t()) :: String.t()
  def authorization_header(endpoint_url) do
    cfg = config!()
    audience = audience_for(endpoint_url)
    jwt = build_jwt(audience, cfg)
    "vapid t=#{jwt}, k=#{cfg.public_key}"
  end

  @doc """
  Returns the configured VAPID public key (URL-safe base64, 65-byte point).
  The client passes this to `pushManager.subscribe({ applicationServerKey })`.
  """
  @spec public_key() :: String.t()
  def public_key, do: config!().public_key

  @doc """
  Returns the origin (scheme + host + non-default port) of a URL — the value
  used as the `aud` claim in the VAPID JWT.
  """
  @spec audience_for(String.t()) :: String.t()
  def audience_for(url) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(url)
    default_port = if scheme == "https", do: 443, else: 80
    port_part = if port && port != default_port, do: ":#{port}", else: ""
    "#{scheme}://#{host}#{port_part}"
  end

  # ── internals ───────────────────────────────────────────────────────────────

  defp build_jwt(audience, cfg) do
    header = %{"typ" => @typ, "alg" => @alg}

    claims = %{
      "aud" => audience,
      "exp" => System.system_time(:second) + @exp_seconds,
      "sub" => cfg.subject
    }

    header_b64 = json_b64(header)
    claims_b64 = json_b64(claims)
    signing_input = header_b64 <> "." <> claims_b64

    raw_sig = sign(signing_input, decode_b64(cfg.private_key))
    signing_input <> "." <> b64url(raw_sig)
  end

  defp sign(msg, priv_key_bytes) do
    der = :crypto.sign(:ecdsa, :sha256, msg, [priv_key_bytes, :secp256r1])
    der_ecdsa_to_raw(der)
  end

  # Convert DER-encoded ECDSA signature (`SEQUENCE { INTEGER r, INTEGER s }`)
  # to the fixed-length raw form expected by JWS ES256 (`r || s`, 64 bytes).
  defp der_ecdsa_to_raw(<<0x30, _seq_len, 0x02, r_len, rest::binary>>),
    do: extract_rs(rest, r_len)

  defp der_ecdsa_to_raw(<<0x30, 0x81, _seq_len, 0x02, r_len, rest::binary>>),
    do: extract_rs(rest, r_len)

  defp extract_rs(rest, r_len) do
    <<r::binary-size(^r_len), 0x02, s_len, s::binary-size(s_len)>> = rest
    pad32(trim_leading_zero(r)) <> pad32(trim_leading_zero(s))
  end

  defp trim_leading_zero(<<0x00, rest::binary>>) when byte_size(rest) > 0,
    do: trim_leading_zero(rest)

  defp trim_leading_zero(bin), do: bin

  defp pad32(bin) when byte_size(bin) == 32, do: bin

  defp pad32(bin) when byte_size(bin) < 32 do
    pad_bits = (32 - byte_size(bin)) * 8
    <<0::size(pad_bits), bin::binary>>
  end

  defp json_b64(map), do: map |> Jason.encode!() |> b64url()

  defp b64url(bin), do: Base.url_encode64(bin, padding: false)

  defp decode_b64(b64), do: Base.url_decode64!(b64, padding: false)

  defp config! do
    cfg = Application.get_env(:sesh_lab, :vapid, [])

    public =
      Keyword.get(cfg, :public_key) ||
        raise "VAPID public_key not configured. Run: mix sesh.gen.vapid"

    private =
      Keyword.get(cfg, :private_key) ||
        raise "VAPID private_key not configured"

    %{
      public_key: public,
      private_key: private,
      subject: Keyword.get(cfg, :subject, "mailto:admin@example.com")
    }
  end
end
