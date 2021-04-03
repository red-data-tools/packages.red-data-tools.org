# README

https://packages.red-data-tools.org/

Package repository for Red Data Tools related projects including
[Apache Arrow](https://github.com/apache/arrow) and
[Apache Parquet](https://github.com/apache/parquet-format).

## Supported packages

  * [OpenCV GLib (C API)](https://github.com/red-data-tools/opencv-glib)
  * [GR framework](https://github.com/sciapp/gr)

## Supported platforms

There are packages for the following platforms:

  * Debian GNU/Linux buster
  * Ubuntu 18.04 LTS
  * Ubuntu 20.04 LTS
  * CentOS 8

## How to add the package repository

https://packages.red-data-tools.org/ provides packages. You need to
enable the package repository before you install packages.

### Debian GNU/Linux and Ubuntu

Run the following command lines to add apt-lines for APT repository on
packages.red-data-tools.org:

```bash
sudo apt install -y -V ca-certificates lsb-release wget
wget https://packages.red-data-tools.org/$(lsb_release --id --short | tr 'A-Z' 'a-z')/red-data-tools-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt install -y -V ./red-data-tools-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt update
```

### CentOS

```bash
(. /etc/os-release && sudo dnf install -y https://packages.red-data-tools.org/centos/${VERSION_ID}/red-data-tools-release-latest.noarch.rpm)
```

## How to install packages

### OpenCV GLib

```bash
sudo apt install libopencv-glib-dev
```

### GR framework

```bash
sudo apt install libgrm-dev
```

```bash
sudo dnf install gr-devel
```

## Development

### How to deploy

```bash
sudo apt install ansible
rake deploy
```

### How to create packages

Here are command lines to build .deb files and update APT repository:

```bash
git submodule update --init --recursive
rake apt
```

Here are command lines to build .rpm files and update Yum repository:

```bash
git submodule update --init --recursive
rake yum
```

## License

Apache-2.0

Copyright 2017-2020 Kouhei Sutou \<kou@clear-code.com\>

See LICENSE and NOTICE for details.
