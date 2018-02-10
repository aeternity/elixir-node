FROM ubuntu:16.04

# DISCLAIMER: this is not optimized and configured well, use carefully

RUN adduser --disabled-password --gecos "" elixir

RUN apt-get update
RUN apt-get install -y curl locales git build-essential

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# install erlang and elixir
RUN curl https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb -o erlang-solutions_1.0_all.deb
RUN dpkg -i erlang-solutions_1.0_all.deb
RUN apt-get update
RUN apt-get install -y esl-erlang=1:20.0 elixir=1.5.1-1

# use elixir user for running
COPY . /elixir_research
WORKDIR /elixir_research
RUN chown -R elixir:elixir /elixir_research
USER elixir

# install rust dependency for rocksdb persistence
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH=/home/elixir/.cargo/env:/home/elixir/.cargo/bin:$PATH

# install hex dependencies
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get

# set environment and set entrypoint
ENV MIX_ENV=docker
ENV SHELL=/bin/sh
EXPOSE 4000
ENTRYPOINT ["iex", "-S", "mix", "phx.server"]
