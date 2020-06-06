FROM centos:8

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf install -y ${quiet} epel-release && \
  dnf install -y --enablerepo=PowerTools ${quiet} \
    cairo-devel \
    cmake \
    fontconfig-devel \
    freetype-devel \
    gcc \
    gcc-c++ \
    libXft-devel \
    libXt-devel \
    libgs-devel \
    libjpeg-devel \
    libtiff-devel \
    make \
    mesa-libGL-devel \
    ncurses \
    qhull-devel \
    qt5-devel \
    rpm-build \
    texlive-dvipng \
    texlive-latex \
    which && \
  dnf clean ${quiet} all
