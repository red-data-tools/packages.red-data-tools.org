FROM centos:8

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf install -y ${quiet} epel-release && \
  dnf install -y --enablerepo=powertools ${quiet} \
    cmake \
    gcc-c++ \
    libarchive \
    make \
    python3 \
    rpm-build && \
  dnf clean ${quiet} all
