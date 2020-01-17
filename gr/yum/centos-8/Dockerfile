FROM centos:8

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf update -y ${quiet} && \
  dnf install -y ${quiet} epel-release && \
  dnf install -y --enablerepo=PowerTools ${quiet} \
    cairo-devel \
    fontconfig-devel \
    freetype-devel \
    gcc \
    gcc-c++ \
    libXt-devel \
    libgs-devel \
    libtiff-devel \
    make \
    mesa-libGL-devel \
    ncurses \
    qt5-devel \
    rpm-build \
    texlive-dvipng \
    texlive-latex \
    which && \
  dnf clean ${quiet} all
