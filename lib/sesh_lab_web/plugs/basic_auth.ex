defmodule SeshLabWeb.Plugs.BasicAuth do
  @moduledoc "Plug fino sobre `Plug.BasicAuth`. Config lido em runtime. 401 renderiza HTML custom."

  import Plug.Conn
  alias SeshLabWeb.ErrorHTML

  @behaviour Plug

  @impl true
  def init(_opts), do: []

  @impl true
  def call(conn, _opts) do
    cfg = Application.fetch_env!(:sesh_lab, :admin_auth)

    with {user, pass} when is_binary(user) <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- Plug.Crypto.secure_compare(user, cfg[:username]),
         true <- Plug.Crypto.secure_compare(pass, cfg[:password]) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body =
      ErrorHTML.render("401.html", %{__changed__: nil})
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_header("www-authenticate", ~s|Basic realm="sesh sesh"|)
    |> put_resp_content_type("text/html")
    |> send_resp(401, body)
    |> halt()
  end
end
