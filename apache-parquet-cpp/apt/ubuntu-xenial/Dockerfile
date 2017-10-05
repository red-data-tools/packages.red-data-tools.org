FROM ubuntu:16.04

ENV DEBIAN_FRONTEND noninteractive

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    apt-transport-https \
    bison \
    build-essential \
    cmake \
    debhelper \
    devscripts \
    flex \
    git \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libboost-system-dev \
    libssl-dev \
    libtool \
    lsb-release \
    pkg-config \
    zlib1g-dev && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*
