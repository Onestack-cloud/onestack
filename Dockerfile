# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bookworm-20241016-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241016-slim
#
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG DEBIAN_VERSION=bookworm-20241016-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential curl ca-certificates git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs=22.23.4-1nodesource1


# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets
WORKDIR assets
RUN node --version
# RUN npm i -g yarn; yarn set version stable
RUN npm ci --no-audit --no-fund
WORKDIR ../

# Keep the configured compiler version available when npm's metadata API fails.
RUN test "$(uname -m)" = "x86_64" \
    && curl --fail --location --retry 3 --max-time 60 \
      https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.17.11.tgz \
      --output /tmp/esbuild.tgz \
    && echo "20784512afbd6ad0c1e7c6a43b4aff71148a5452166c67f43b4983b3e7a9d3d5  /tmp/esbuild.tgz" | sha256sum --check - \
    && tar -xzf /tmp/esbuild.tgz -C /tmp package/bin/esbuild \
    && install -m 755 /tmp/package/bin/esbuild /app/_build/esbuild-linux-x64 \
    && test "$(/app/_build/esbuild-linux-x64 --version)" = "0.17.11" \
    && rm -rf /tmp/esbuild.tgz /tmp/package

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Create a directory for environment files
RUN mkdir -p /app/env && chown nobody /app/env

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/onestack ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

LABEL org.opencontainers.image.source=https://github.com/Onestack-cloud/onestack
LABEL org.opencontainers.image.description="Onestack: manage open source alternatives to SaaS tools from a single dashboard"
LABEL org.opencontainers.image.licenses=AGPL-3.0

CMD ["/app/bin/migrate_and_server"]
