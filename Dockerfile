# Multi-stage Phoenix release for sesh-lab (sqlite, no node).
# Update ARG tags if you bump Elixir/OTP/Debian. Match your local versions.
#
# Use bookworm (glibc 2.36) not bullseye (glibc 2.31): exqlite ships
# precompiled NIFs that require glibc >= 2.33, so bullseye runtime crashes
# at boot with `version GLIBC_2.33 not found` when loading sqlite3_nif.so.
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=bookworm-20260518-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential git curl libsqlite3-dev pkg-config && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# esbuild only (no node, no tailwind)
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# ---------------------------------------------------------------------------
FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates libsqlite3-0 && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

ENV DATABASE_PATH=/data/sesh.db
RUN mkdir -p /data /data/uploads/products

ENV MIX_ENV=prod
COPY --from=builder /app/_build/${MIX_ENV}/rel/sesh_lab ./

# NOTE: container runs as root. Fly volume mounted at /data is owned by root
# on first mount; app reads/writes sesh.db and /data/uploads. Single-tenant
# hobby app — acceptable. Multi-user would want privilege drop.

CMD ["/app/bin/server"]
