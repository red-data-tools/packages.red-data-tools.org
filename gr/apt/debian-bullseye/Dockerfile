FROM debian:bullseye

RUN \
  echo "debconf debconf/frontend select Noninteractive" | \
    debconf-set-selections

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "-qq") && \
  apt update ${quiet} && \
  apt install -y -V ${quiet} \
    cmake \
    debhelper \
    devscripts \
    dvipng \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libbz2-dev \
    libcairo2-dev \
    libfreetype6-dev \
    libgl-dev \
    libglfw3-dev \
    libgs-dev \
    libjpeg-dev \
    libogg-dev \
    libpng-dev \
    libqhull-dev \
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
    qtbase5-dev \
    texlive-latex-base \
    zlib1g-dev && \
  apt clean
