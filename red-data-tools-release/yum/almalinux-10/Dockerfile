FROM almalinux:10

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf update -y ${quiet} && \
  dnf install -y ${quiet} \
    rpm-build && \
  dnf clean ${quiet} all
