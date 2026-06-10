defmodule SeshLab.Clock do
  @moduledoc """
  Helpers de tempo. Banco guarda UTC; UI exibe America/Sao_Paulo.
  """

  @tz "America/Sao_Paulo"

  @spec tz() :: String.t()
  def tz, do: @tz

  @spec now_utc() :: DateTime.t()
  def now_utc, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @spec now_brt() :: DateTime.t()
  def now_brt, do: DateTime.now!(@tz)

  @spec to_brt(DateTime.t() | NaiveDateTime.t() | nil) :: DateTime.t() | nil
  def to_brt(nil), do: nil

  def to_brt(%DateTime{} = dt), do: DateTime.shift_zone!(dt, @tz)

  def to_brt(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.shift_zone!(@tz)
  end

  @spec format(DateTime.t() | NaiveDateTime.t() | nil, :date | :time | :datetime) :: String.t()
  def format(nil, _), do: ""

  def format(dt, kind) do
    case to_brt(dt) do
      %DateTime{} = brt -> do_format(brt, kind)
    end
  end

  defp do_format(%DateTime{} = dt, :date),
    do: pad2(dt.day) <> "/" <> pad2(dt.month) <> "/" <> Integer.to_string(dt.year)

  defp do_format(%DateTime{} = dt, :time), do: pad2(dt.hour) <> ":" <> pad2(dt.minute)

  defp do_format(%DateTime{} = dt, :datetime),
    do: do_format(dt, :date) <> " " <> do_format(dt, :time)

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
