FROM centos:7

ARG DEBUG

RUN \
  quiet=$([ "${DEBUG}" = "yes" ] || echo "--quiet") && \
  yum update -y ${quiet} && \
  yum install -y ${quiet} \
    epel-release \
    https://packages.red-data-tools.org/centos/red-data-tools-release-1.0.0-1.noarch.rpm && \
  yum groupinstall -y ${quiet} "Development Tools" && \
  yum install -y ${quiet} \
    arrow-devel \
    cmake3 \
    git \
    openssl-devel \
    rpm-build \
    rpmdevtools && \
  yum clean ${quiet} all

RUN yum install -y boost-devel
