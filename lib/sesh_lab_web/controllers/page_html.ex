defmodule SeshLabWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use SeshLabWeb, :html

  alias SeshLab.Clock

  embed_templates "page_html/*"

  @doc "URL da arte custom da edição (nil se não houver upload → usa o vetor oficial)."
  def edition_logo(edition), do: SeshLab.Editions.logo_url(edition.logo_path)

  @months ~w(JAN FEV MAR ABR MAI JUN JUL AGO SET OUT NOV DEZ)

  @doc ~S|Dia da edição no formato duo-color: `27JUN.` (em BRT).|
  def edition_day(starts_at) do
    brt = Clock.to_brt(starts_at)
    "#{brt.day}#{Enum.at(@months, brt.month - 1)}."
  end

  @doc ~S|Horário da edição: `21H` (BRT, hora cheia; mostra minutos só se houver).|
  def edition_time(starts_at) do
    brt = Clock.to_brt(starts_at)

    case brt.minute do
      0 -> "#{brt.hour}H"
      m -> "#{brt.hour}H#{String.pad_leading(Integer.to_string(m), 2, "0")}"
    end
  end

  @doc "Lineup é texto livre, um nome por linha. Quebra em lista limpa."
  def lineup_lines(nil), do: []

  def lineup_lines(lineup) do
    lineup
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
