# SESH LAB

Site do coletivo SESH: a landing estilo flyer da próxima edição mais a venda de
ingresso digital, com PIX manual e validação de QR na porta. A primeira edição
já rolou e deu certo, então isto aqui virou a casa oficial do rolê.

A SESH é um rolê experimental pra formar comunidade em torno de música
eletrônica em todos os formatos. Um espaço acessível pra quem quer curtir e pros
DJs novos que precisam de lugar pra se lançar. Baguncinha no início, os DJs
trocando ideia sobre produção, e muita música estranha até as 5h da manhã.

## Por que existe

Coletivo pequeno não precisa de Sympla cobrando taxa, nem de gateway de
pagamento, nem de planilha no grupo pra saber quem pagou. Precisa de:

- uma página que pareça o flyer da edição e carregue rápido no celular na fila da porta;
- vender ingresso recebendo PIX direto na chave do coletivo (confirmação manual via Instagram, sem API de pagamento);
- emitir ingresso ao portador com QR pra validar na entrada — câmera ou código curto digitado na mão como fallback;
- um canal pros DJs novos mandarem set ("Quero tocar!") e pro público pedir aviso de nova edição.

Tudo isso roda numa VM única e barata. Sem dependência externa que possa cair
(ou cobrar) no meio do evento.

## Stack

- Phoenix 1.8 + LiveView 1.1
- SQLite via `ecto_sqlite3` (um arquivo, um volume, fim)
- esbuild puro pra JS e CSS — sem Tailwind, sem Node em runtime, sem CDN
- PWA com service worker manual, manifest e ícones
- PIX EMV BR Code gerado na unha (`lib/sesh_lab/payments/pix.ex`)
- Web Push VAPID manual, RFC completo (`lib/sesh_lab/notifications/web_push/`)
- Bandit como servidor

Domínio do app: edições → lotes → pedidos → ingressos emitidos → validação na
porta. Whitelabel do `cozinha_radioativa` — mesma infra, domínio e estética
novos.

Estética: Y2K cyber-rave. Caixas wireframe, blobs rosa, tipografia pixel,
textura grain. Copy em pt-BR, sem nomes pessoais no site, sem emoji.

## Dev local

Requer Elixir 1.19, OTP 28 e SQLite.

```sh
source .env       # ADMIN_USER, ADMIN_PASS, PIX_KEY (valores de dev ficam no repo local)
mix setup
mix phx.server
```

- Público: http://localhost:4000
- Admin: http://localhost:4000/admin (basic auth via `.env`)

## Spec

`SPEC_SESH_LAB.md` tem arquitetura, schemas, fluxos e roadmap por fase.

## Deploy

Fly.io, máquina única com volume pra SQLite (`fly.toml`). Migrações rodam no boot
via `Ecto.Migrator`. Em dia de evento, sobe `min_machines_running = 1` — cold
start no meio da fila da porta não rola.
