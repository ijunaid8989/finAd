# This Dockerfile is optimized for Phoenix applications with assets
# Works with Render, Fly.io, and other container platforms

FROM hexpm/elixir:1.15.7-erlang-26.2.2-alpine-3.19.1 AS build

RUN apk add --no-cache build-base git npm

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./

RUN mix deps.get --only prod

RUN mix deps.compile

COPY config ./config

COPY lib ./lib

COPY priv ./priv

ENV MIX_ENV=prod

RUN mix compile

COPY assets ./assets

RUN mix deps.get --only dev

RUN mix assets.deploy

RUN mix phx.digest

RUN mix phx.gen.release

RUN mix release

FROM alpine:3.19.0 AS app

RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/financial_advisor ./

ENV HOME=/app

ENV MIX_ENV=prod

ENV PHX_SERVER=true

EXPOSE 4000

CMD ["./bin/financial_advisor", "start"]

