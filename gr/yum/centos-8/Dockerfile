FROM centos:8

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  # TODO: qt5-devel requires LLVM 7 for now.
  # CentOS 8.0.1905 provides LLVM 7 but CentOS 8.1.1911 provides only
  # LLVM 8.
  sed -i'' \
    -e 's/^mirrorlist/#mirrorlist/' \
    -e 's/^#baseurl/baseurl/' \
    -e 's/$releasever/8.0.1905/g' \
    /etc/yum.repos.d/*.repo && \
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
