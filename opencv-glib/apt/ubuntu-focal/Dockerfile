FROM ubuntu:focal

RUN \
  echo "debconf debconf/frontend select Noninteractive" | \
    debconf-set-selections

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    apt-transport-https \
    build-essential \
    debhelper \
    devscripts \
    gtk-doc-tools \
    libgirepository1.0-dev \
    libglib2.0-doc \
    libopencv-dev \
    lsb-release \
    meson \
    pkg-config \
    ruby-gobject-introspection && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*
