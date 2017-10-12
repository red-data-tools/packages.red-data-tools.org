FROM debian:stretch

ENV DEBIAN_FRONTEND noninteractive

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    apt-transport-https \
    build-essential \
    debhelper \
    devscripts \
    libgirepository1.0-dev \
    libglib2.0-doc \
    lsb-release \
    gtk-doc-tools \
    pkg-config && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*
