FROM centos:7

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  yum update -y ${quiet} && \
  yum install -y ${quiet} epel-release && \
  yum groupinstall -y ${quiet} "Development Tools" && \
  yum install -y ${quiet} \
    gtk-doc \
    gobject-introspection-devel \
    pkg-config \
    rpm-build \
    rpmdevtools && \
  yum clean ${quiet} all
