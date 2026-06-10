defmodule SeshLabWeb.Plugs.Accent do
  @moduledoc """
  Assina `@accent` com a cor da edição publicada para que TODA página (pública
  e admin, dead view e LiveView) se re-tematize via a CSS var `--accent`.

  Sem edição publicada → não assina nada e o `tokens.css` cai no rosa padrão.
  Controllers podem sobrescrever `@accent` depois (ex: a página de compra usa o
  accent da edição específica do pedido).
  """

  import Plug.Conn

  alias SeshLab.Editions

  def init(opts), do: opts

  def call(conn, _opts) do
    case Editions.current_accent() do
      color when is_binary(color) -> assign(conn, :accent, color)
      _ -> conn
    end
  end
end
