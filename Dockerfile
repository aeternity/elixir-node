FROM ubuntu:16.04

# DISCLAIMER: this is not optimized and configured well, use carefully

RUN adduser --disabled-password --gecos "" elixir

RUN apt-get update
RUN apt-get install -y curl locales git build-essential autoconf autogen libtool libgmp3-dev

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# install erlang and elixir
RUN curl https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb -o erlang-solutions_1.0_all.deb
RUN dpkg -i erlang-solutions_1.0_all.deb
RUN apt-get update
RUN apt-get install -y esl-erlang=1:20.2.2 elixir=1.6.1-1

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
RUN mix deps.get
RUN mix deps.compile
RUN mix compile

# set entrypoint
EXPOSE 4000
ENTRYPOINT ["iex", "-S", "mix", "phx.server"]
