defmodule SeshLab.Notifications.WebPush.Encryption do
  @moduledoc """
  `aes128gcm` content encoding (RFC 8188) layered over the Web Push message
  encryption (RFC 8291).

  Encrypts a plaintext payload into the binary body POSTed to the push service
  endpoint. The receiving user agent decrypts it with the subscription's
  private key + auth secret and hands the plaintext to the service worker's
  `push` event.

  Single-record only: payloads must fit in `record_size - 17` bytes (4079 for
  the default 4096). Our notifications are < 250 bytes, so we never split.
  """

  @record_size 4096

  @doc """
  Returns the binary body to POST. `p256dh` and `auth` come straight from the
  PushSubscription stored in the DB (URL-safe base64, no padding).

  Generates a fresh application-server ECDH keypair and salt for each call.
  """
  @spec encrypt(plaintext :: binary(), p256dh :: String.t(), auth :: String.t()) :: binary()
  def encrypt(plaintext, p256dh, auth) when is_binary(plaintext) do
    keypair = :crypto.generate_key(:ecdh, :prime256v1)
    salt = :crypto.strong_rand_bytes(16)
    encrypt_with(plaintext, p256dh, auth, keypair, salt)
  end

  @doc """
  Same as `encrypt/3` but takes the application-server keypair and salt
  explicitly, making the output deterministic. Exposed for testing against
  RFC 8291 §5 vectors; production callers should use `encrypt/3`.
  """
  @spec encrypt_with(
          plaintext :: binary(),
          p256dh :: String.t(),
          auth :: String.t(),
          keypair :: {binary(), binary()},
          salt :: binary()
        ) :: binary()
  def encrypt_with(plaintext, p256dh, auth, {as_public, as_private}, salt)
      when is_binary(plaintext) do
    ua_public = Base.url_decode64!(p256dh, padding: false)
    auth_secret = Base.url_decode64!(auth, padding: false)

    # Sanity — wrong sizes here mean a corrupt subscription.
    65 = byte_size(ua_public)
    16 = byte_size(auth_secret)
    16 = byte_size(salt)

    ecdh_secret = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)

    # ── RFC 8291 §3.3: derive the input keying material ───────────────────────
    prk_key = hmac(auth_secret, ecdh_secret)
    key_info = "WebPush: info" <> <<0>> <> ua_public <> as_public
    ikm = hkdf_expand(prk_key, key_info, 32)

    # ── RFC 8188: derive CEK + nonce ──────────────────────────────────────────
    prk = hmac(salt, ikm)
    cek = hkdf_expand(prk, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf_expand(prk, "Content-Encoding: nonce" <> <<0>>, 12)

    # Single-record padding delimiter: 0x02 marks "last record".
    padded = plaintext <> <<2>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, padded, <<>>, true)

    # aes128gcm content-coding header (RFC 8188 §2.1):
    #   salt(16) || rs(uint32 BE) || idlen(uint8) || keyid(idlen=65, = as_public)
    salt <>
      <<@record_size::32>> <>
      <<byte_size(as_public)>> <>
      as_public <>
      ciphertext <>
      tag
  end

  # HKDF-Expand bounded to a single HMAC output block; all our uses need ≤ 32 bytes.
  defp hkdf_expand(prk, info, length) when length <= 32 do
    prk |> hmac(info <> <<1>>) |> binary_part(0, length)
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
end
