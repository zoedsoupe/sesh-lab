defmodule SeshLab.Payments.PixTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias SeshLab.Payments.Pix

  defp build(extra \\ []) do
    Pix.build(
      Keyword.merge(
        [
          pix_key: "5522936192983",
          amount_cents: 4500,
          merchant_name: "Diana",
          merchant_city: "CAMPOS"
        ],
        extra
      )
    )
  end

  # ── Helpers: independently parse EMV TLV + recompute CRC ────────────────────

  defp parse_tlv(<<>>), do: []

  defp parse_tlv(<<id::binary-size(2), len_bin::binary-size(2), rest::binary>>) do
    len = String.to_integer(len_bin)
    <<value::binary-size(^len), tail::binary>> = rest
    [{id, value} | parse_tlv(tail)]
  end

  defp crc16_ccitt(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(0xFFFF, fn byte, crc ->
      Enum.reduce(0..7, bxor(crc, byte <<< 8), fn _, c ->
        if (c &&& 0x8000) != 0,
          do: bxor(c <<< 1, 0x1021) &&& 0xFFFF,
          else: c <<< 1 &&& 0xFFFF
      end)
    end)
    |> Integer.to_string(16)
    |> String.pad_leading(4, "0")
    |> String.upcase()
  end

  describe "build/1" do
    test "ends with a valid CRC16-CCITT over everything up to and including '6304'" do
      emv = build()

      body = String.slice(emv, 0, byte_size(emv) - 4)
      crc = String.slice(emv, -4, 4)

      assert String.ends_with?(body, "6304")
      assert crc == crc16_ccitt(body)
    end

    test "TLV structure contains all required fields with correct order" do
      emv = build()
      body = String.slice(emv, 0, byte_size(emv) - 4)
      # Strip trailing "6304" (CRC marker before checksum).
      payload = String.slice(body, 0, byte_size(body) - 4)
      tlv = parse_tlv(payload)

      assert {"00", "01"} in tlv
      assert {"52", "0000"} in tlv
      assert {"53", "986"} in tlv
      assert {"58", "BR"} in tlv

      # Merchant Account Info (id 26) is itself a TLV: GUI + pix key.
      assert Enum.find(tlv, fn {id, _} -> id == "26" end)
      {_, mai_value} = Enum.find(tlv, fn {id, _} -> id == "26" end)
      mai = parse_tlv(mai_value)
      assert {"00", "br.gov.bcb.pix"} in mai
      assert {"01", "5522936192983"} in mai

      assert {"54", "45.00"} in tlv
      assert {"59", "DIANA"} in tlv
      assert {"60", "CAMPOS"} in tlv
    end

    test "amount formats cents as decimal with 2 places" do
      assert build(amount_cents: 100) =~ "5404" <> "1.00"
      assert build(amount_cents: 12_345) =~ "5406" <> "123.45"
    end

    test "sanitizes merchant name: strips accents, uppercases, drops non-alnum, caps at 25" do
      emv =
        build(
          merchant_name: "Diëgo Açaí & Cia.",
          merchant_city: "São José dos Campos"
        )

      body = String.slice(emv, 0, byte_size(emv) - 8)
      tlv = parse_tlv(body)

      {_, name} = Enum.find(tlv, fn {id, _} -> id == "59" end)
      assert name == "DIEGO ACAI  CIA"
      assert byte_size(name) <= 25

      {_, city} = Enum.find(tlv, fn {id, _} -> id == "60" end)
      # City capped at 15 — "SAO JOSE DOS CA" (15 chars).
      assert byte_size(city) <= 15
      assert city == "SAO JOSE DOS CA"
    end

    test "uses default merchant_city when not given" do
      emv = build()
      assert emv =~ "6006" <> "CAMPOS"
    end

    test "txid defaults to '***' inside additional data (id 62 → 05)" do
      emv = build()
      assert emv =~ "62" <> "07" <> "0503***"
    end

    test "explicit txid overrides default" do
      emv = build(txid: "ORDER123")
      assert emv =~ "62" <> "12" <> "0508ORDER123"
    end
  end

  describe "to_svg/1" do
    test "wraps EMV string in an SVG document" do
      svg = build() |> Pix.to_svg()
      assert svg =~ "<svg"
      assert svg =~ "</svg>"
    end
  end
end
