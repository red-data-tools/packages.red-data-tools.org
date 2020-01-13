FROM centos:8

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  dnf update -y ${quiet} && \
  dnf install -y ${quiet} \
    "dnf-command(config-manager)" \
    rpm-build && \
  dnf clean ${quiet} all
