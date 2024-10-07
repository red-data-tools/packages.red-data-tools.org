FROM almalinux:9

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf install -y ${quiet} epel-release && \
  dnf install -y --enablerepo=crb ${quiet} \
    ccache \
    cmake \
    gcc-c++ \
    libarchive \
    make \
    python3 \
    rpm-build && \
  dnf clean ${quiet} all
