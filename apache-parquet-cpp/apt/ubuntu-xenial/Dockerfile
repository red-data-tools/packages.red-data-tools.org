FROM ubuntu:16.04

ENV DEBIAN_FRONTEND noninteractive

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    apt-transport-https \
    lsb-release && \
  echo "deb https://packages.red-data-tools.org/ubuntu/ $(lsb_release --codename --short) universe" \
    > /etc/apt/sources.list.d/red-data-tools.list && \
  apt update ${quiet} --allow-insecure-repositories && \
  apt install -y -V ${quiet} --allow-unauthenticated red-data-tools-keyring && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    bison \
    build-essential \
    cmake \
    debhelper \
    devscripts \
    flex \
    git \
    libarrow-dev \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libboost-system-dev \
    libssl-dev \
    libtool \
    pkg-config \
    zlib1g-dev && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*
