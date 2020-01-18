# README

https://packages.red-data-tools.org/ provides packages for Red Data
Tools related projects including Apache Arrow and Apache Parquet.

## Supported packages

  * OpenCV GLib (C API)
  * GR framework

## Supported platforms

There are packages for the following platforms:

  * Debian GNU/Linux buster
  * Ubuntu 18.04 LTS
  * Ubuntu 19.04
  * CentOS 8

## Package repository

https://packages.red-data-tools.org/ provides packages. You need to
enable the package repository before you install packages.

### Debian GNU/Linux and Ubuntu

Run the following command lines to add apt-lines for APT repository on
packages.red-data-tools.org:

```console
% sudo apt install -y -V lsb-release wget
% wget https://packages.red-data-tools.org/$(lsb_release --id --short | tr 'A-Z' 'a-z')/red-data-tools-archive-keyring-latest-$(lsb_release --codename --short).deb
% sudo apt install -y -V ./red-data-tools-archive-keyring-latest-$(lsb_release --codename --short).deb
% sudo apt update
```

### CentOS

```console
% (. /etc/os-release && sudo dnf install -y https://packages.red-data-tools.org/centos/${VERSION_ID}/red-data-tools-release-latest.noarch.rpm)
```

## OpenCV GLib

This section describes how to install
[OpenCV GLib](https://github.com/red-data-tools/opencv-glib) package.

### Debian GNU/Linux and Ubuntu

```console
% sudo apt install -y -V libopencv-glib-dev
```

## GR framework

This section describes how to install
[GR framework](https://gr-framework.org/) package.

### Debian GNU/Linux and Ubuntu

```console
% sudo apt install -y -V libgr3-dev
```

### CentOS

```console
% sudo dnf install -y gr
```

## For packages.red-data-tools.org administrator

### How to deploy

```console
% sudo apt install -V ansible
% rake deploy
```

## For package creators

### Debian GNU/Linux and Ubuntu

Here are command lines to build .deb files and update APT repository:

```console
% git submodule update --init
% rake apt
```

### CentOS

Here are command lines to build .rpm files and update Yum repository:

```console
% git submodule update --init
% rake yum
```

## License

Apache-2.0

Copyright 2017-2019 Kouhei Sutou \<kou@clear-code.com\>

See LICENSE and NOTICE for details.
