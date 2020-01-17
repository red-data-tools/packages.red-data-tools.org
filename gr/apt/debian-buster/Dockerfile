FROM debian:buster

RUN \
  echo "debconf debconf/frontend select Noninteractive" | \
    debconf-set-selections

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    debhelper \
    devscripts \
    dvipng \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libcairo2-dev \
    libfreetype6-dev \
    libgl-dev \
    libglfw3-dev \
    libgs-dev \
    libjpeg-dev \
    libogg-dev \
    libpng-dev \
    libswscale-dev \
    libtheora-dev \
    libtiff-dev \
    libvpx-dev \
    libwxgtk3.0-gtk3-dev \
    libxcursor-dev \
    libxft-dev \
    libxi-dev \
    libxinerama-dev \
    libxt-dev \
    libzmq3-dev \
    python \
    qt5-default \
    texlive-latex-base \
    zlib1g-dev && \
  apt clean && \
  rm -rf /var/lib/apt/lists/*
