defmodule SeshLab.Notifications.WebPush.EncryptionTest do
  use ExUnit.Case, async: true

  alias SeshLab.Notifications.WebPush.Encryption

  # ── RFC 8291 §5 — push message encryption example ───────────────────────────
  # https://datatracker.ietf.org/doc/html/rfc8291#section-5
  @plaintext "When I grow up, I want to be a watermelon"

  @ua_public_b64 "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
  @auth_b64 "BTBZMqHH6r4Tts7J_aSIgg"

  @as_public_b64 "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
  @as_private_b64 "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"

  @salt_b64 "DGv6ra1nlYgDCS1FRnbzlw"

  @expected_body_b64 "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"

  test "encrypt_with/5 matches RFC 8291 §5 vector byte-for-byte" do
    as_keypair = {b64d(@as_public_b64), b64d(@as_private_b64)}
    salt = b64d(@salt_b64)

    body = Encryption.encrypt_with(@plaintext, @ua_public_b64, @auth_b64, as_keypair, salt)
    expected = b64d(@expected_body_b64)

    assert body == expected
  end

  test "encrypt/3 produces a different ciphertext every call (fresh ephemeral + salt)" do
    body1 = Encryption.encrypt("ping", @ua_public_b64, @auth_b64)
    body2 = Encryption.encrypt("ping", @ua_public_b64, @auth_b64)

    refute body1 == body2
  end

  test "encrypt/3 output respects aes128gcm header shape" do
    body = Encryption.encrypt("ping", @ua_public_b64, @auth_b64)

    <<_salt::binary-size(16), rs::32, idlen, keyid::binary-size(65), payload::binary>> = body

    assert rs == 4096
    assert idlen == 65
    # uncompressed P-256 point begins with 0x04.
    assert :binary.first(keyid) == 0x04
    # payload = ciphertext(plaintext + 1 delimiter byte) + 16-byte GCM tag.
    assert byte_size(payload) == byte_size("ping") + 1 + 16
  end

  defp b64d(s), do: Base.url_decode64!(s, padding: false)
end
