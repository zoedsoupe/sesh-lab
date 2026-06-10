defmodule Mix.Tasks.Sesh.Gen.Vapid do
  @moduledoc """
  Gera um par de chaves VAPID (P-256) para Web Push.

  ## Uso

      mix sesh.gen.vapid

  Imprime as chaves prontas pra colar em `config/dev.exs` ou pra exportar
  como variáveis de ambiente em produção (`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`).

  A pública (65 bytes uncompressed, base64url sem padding) também é o valor
  que o cliente passa em `pushManager.subscribe({ applicationServerKey })`.
  """

  use Mix.Task

  @shortdoc "Gera par de chaves VAPID P-256 pra Web Push"

  @impl Mix.Task
  def run(_args) do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)

    public_b64 = b64url(public)
    private_b64 = b64url(private)

    IO.puts("""

    # ─── VAPID keypair ─────────────────────────────────────────────────────────

    ## config/dev.exs (ou config/runtime.exs em prod)
    config :sesh_lab, :vapid,
      public_key: "#{public_b64}",
      private_key: "#{private_b64}",
      subject: "mailto:diana@sesh.sesh"

    ## env vars (produção)
    export VAPID_PUBLIC_KEY="#{public_b64}"
    export VAPID_PRIVATE_KEY="#{private_b64}"
    export VAPID_SUBJECT="mailto:diana@sesh.sesh"

    ## Tamanhos (sanity check)
    public  = #{byte_size(public)} bytes
    private = #{byte_size(private)} bytes
    """)
  end

  defp b64url(bin), do: Base.url_encode64(bin, padding: false)
end
