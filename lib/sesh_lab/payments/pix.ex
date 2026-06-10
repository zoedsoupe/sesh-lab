defmodule SeshLab.Payments.Pix do
  @moduledoc """
  Gera código PIX estático no padrão EMV BR Code.

  Spec: https://www.bcb.gov.br/content/estabilidadefinanceira/forumpireunioes/Anexo%20I%20-%20Manual%20do%20BR%20Code.pdf
  """
  import Bitwise

  @merchant_city "CAMPOS"

  @spec build(keyword()) :: String.t()
  def build(opts) do
    key = Keyword.fetch!(opts, :pix_key)
    amount = Keyword.fetch!(opts, :amount_cents)
    merchant_name = Keyword.fetch!(opts, :merchant_name)
    txid = Keyword.get(opts, :txid, "***")
    city = Keyword.get(opts, :merchant_city, @merchant_city)

    payload =
      tlv("00", "01") <>
        tlv("26", tlv("00", "br.gov.bcb.pix") <> tlv("01", key)) <>
        tlv("52", "0000") <>
        tlv("53", "986") <>
        tlv("54", format_amount(amount)) <>
        tlv("58", "BR") <>
        tlv("59", sanitize(merchant_name, 25)) <>
        tlv("60", sanitize(city, 15)) <>
        tlv("62", tlv("05", txid))

    crc_payload = payload <> "6304"
    crc_payload <> crc16_ccitt(crc_payload)
  end

  @spec to_svg(String.t()) :: String.t()
  def to_svg(emv_string) do
    emv_string
    |> EQRCode.encode()
    |> EQRCode.svg(width: 280, color: "#e8e6e3", background_color: "#000000")
  end

  defp tlv(id, value) do
    len = value |> byte_size() |> Integer.to_string() |> String.pad_leading(2, "0")
    id <> len <> value
  end

  defp format_amount(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp sanitize(str, max) do
    str
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/[^A-Za-z0-9 ]/u, "")
    |> String.upcase()
    |> String.slice(0, max)
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
end
