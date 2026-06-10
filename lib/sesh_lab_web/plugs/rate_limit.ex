defmodule SeshLabWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limit por IP via ETS (sem deps). Janela deslizante simples por bucket.

  Uso: `plug SeshLabWeb.Plugs.RateLimit, max: 5, window_ms: 3_600_000, bucket: "tocar"`

  Excedido → 429 e `halt`. App single-node (SQLite), então ETS local basta.
  """

  import Plug.Conn

  @table :sesh_rate_limit

  def init(opts) do
    %{
      max: Keyword.get(opts, :max, 5),
      window_ms: Keyword.get(opts, :window_ms, 3_600_000),
      bucket: Keyword.get(opts, :bucket, "default")
    }
  end

  def call(conn, %{max: max, window_ms: window_ms, bucket: bucket}) do
    ensure_table()
    key = {bucket, client_ip(conn)}
    now = System.monotonic_time(:millisecond)

    hits =
      :ets.lookup(@table, key)
      |> case do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 > now - window_ms))
        [] -> []
      end

    if length(hits) >= max do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(429, "muitas tentativas. tenta de novo mais tarde.")
      |> halt()
    else
      :ets.insert(@table, {key, [now | hits]})
      conn
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
