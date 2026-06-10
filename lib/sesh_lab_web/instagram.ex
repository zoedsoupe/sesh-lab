defmodule SeshLabWeb.Instagram do
  @moduledoc """
  Helpers de link p/ Instagram. DM via `ig.me/m/<handle>` (deep-link
  oficial), fallback profile.

  Instagram **não aceita** pré-preenchimento de mensagem via URL —
  diferente do `wa.me?text=`. Por isso só abrimos a conversa, sem template.
  """

  @spec dm_url(String.t() | nil) :: String.t() | nil
  def dm_url(nil), do: nil
  def dm_url(""), do: nil

  def dm_url(handle) do
    "https://ig.me/m/" <> sanitize(handle)
  end

  @spec profile_url(String.t() | nil) :: String.t() | nil
  def profile_url(nil), do: nil
  def profile_url(""), do: nil

  def profile_url(handle) do
    "https://instagram.com/" <> sanitize(handle)
  end

  defp sanitize(handle) do
    handle
    |> String.trim()
    |> String.trim_leading("@")
    |> String.downcase()
  end
end
