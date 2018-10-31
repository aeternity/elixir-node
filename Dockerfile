FROM ubuntu:18.04

# DISCLAIMER: this is not optimized and configured well, use carefully

RUN adduser --disabled-password --gecos "" elixir

RUN apt-get -qq update
RUN apt-get install -y curl locales git build-essential autoconf autogen libtool libgmp3-dev libssl1.0.0

RUN LIBSODIUM_VERSION=1.0.16 \
    && LIBSODIUM_DOWNLOAD_URL="https://github.com/jedisct1/libsodium/releases/download/${LIBSODIUM_VERSION}/libsodium-${LIBSODIUM_VERSION}.tar.gz" \
    && curl -fsSL -o libsodium-src.tar.gz "$LIBSODIUM_DOWNLOAD_URL" \
    && mkdir libsodium-src \
    && tar -zxf libsodium-src.tar.gz -C libsodium-src --strip-components=1 \
    && cd libsodium-src \
    && ./configure && make -j$(nproc) && make install && ldconfig

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# install erlang and elixir
RUN curl https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb -o erlang-solutions_1.0_all.deb
RUN dpkg -i erlang-solutions_1.0_all.deb
RUN apt-get update
RUN apt-get install -y esl-erlang=1:20.3 elixir=1.6.6-1

# install rust dependency for rocksdb persistence
USER elixir
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH=/home/elixir/.cargo/env:/home/elixir/.cargo/bin:$PATH

# copy source
USER root
WORKDIR /elixir_node
COPY . /elixir_node
RUN chown -R elixir:elixir /elixir_node
USER elixir

# set environment
ENV MIX_ENV=docker
ENV SHELL=/bin/sh

# install hex dependencies
RUN mix local.hex --force
RUN mix local.rebar --force
RUN make clean-deps-compile

# set entrypoint
EXPOSE 4000
EXPOSE 3015
ENTRYPOINT ["iex", "-S", "mix", "phx.server"]
