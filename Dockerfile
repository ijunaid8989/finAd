# This Dockerfile is optimized for Phoenix applications with assets
# Works with Render, Fly.io, and other container platforms

# Stage 1: Build assets
FROM hexpm/elixir:1.15.7-erlang-26.2.2.1-alpine-3.19.0 AS assets-builder

RUN apk add --no-cache build-base git npm

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install Node.js dependencies for assets
COPY assets/package*.json ./assets/
RUN cd assets && npm install || true

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy assets
COPY assets ./assets
COPY config ./config
COPY priv ./priv
COPY lib ./lib

# Build assets
RUN mix assets.deploy

# Stage 2: Build release
FROM hexpm/elixir:1.15.7-erlang-26.2.2.1-alpine-3.19.0 AS release-builder

RUN apk add --no-cache build-base git

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY config ./config
COPY lib ./lib
COPY priv ./priv

# Copy compiled assets from assets-builder
COPY --from=assets-builder /app/priv/static ./priv/static

# Compile and build release
RUN mix compile && \
    mix phx.gen.release && \
    MIX_ENV=prod mix release

# Stage 3: Runtime
FROM alpine:3.19.0 AS runtime

RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    ca-certificates \
    libstdc++

WORKDIR /app

# Create non-root user
RUN adduser -D -s /bin/sh elixir

# Copy release from builder
COPY --from=release-builder --chown=elixir:elixir /app/_build/prod/rel/financial_advisor ./

USER elixir

EXPOSE 8080

ENV PHX_SERVER=true
ENV PORT=8080

CMD ["./bin/server"]

