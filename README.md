# SESH LAB

Site do coletivo SESH: landing page estilo flyer + venda de ingresso digital
com PIX manual e validação de QR na porta. Phoenix 1.8 + SQLite + LiveView,
sem JS pesado, sem CDN, sem deps de UI.

Whitelabel do `cozinha_radioativa` — mesma infra (PIX EMV, Web Push manual,
PWA, Fly single VM), domínio novo: edições → lotes → pedidos → ingressos.

## Stack

- Phoenix 1.8 + LiveView 1.1
- SQLite via `ecto_sqlite3`
- esbuild (JS + CSS), sem Tailwind, sem Node em runtime
- PWA com service worker manual, manifest + ícones
- PIX EMV BR Code gerado manualmente (`lib/sesh_lab/payments/pix.ex`)
- Web Push VAPID manual (`lib/sesh_lab/notifications/web_push/`)

## Dev local

Requer Elixir 1.19.5, OTP 28, SQLite.

```sh
source .env       # ADMIN_USER, ADMIN_PASS, PIX_KEY (valores dev no repo local)
mix setup
mix phx.server
```

- Público: http://localhost:4000
- Admin: http://localhost:4000/admin (basic auth via `.env`)

## Spec

Ver `SPEC_SESH_LAB.md` — arquitetura, schemas, fluxos e roadmap por fase.

## Deploy

Fly.io, máquina única com volume pra SQLite (`fly.toml`). Migrações rodam no
boot via `Ecto.Migrator`. Em dia de evento, setar `min_machines_running = 1`
(cold start no meio da fila da porta não rola).
