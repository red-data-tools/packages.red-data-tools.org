# README

Packages for Apache Arrow and related projects.

## Supported packages

  * Apache Arrow C++
  * Apache Arrow GLib (C API)
  * Apache Parquet C++

## Supported platforms

There are packages for the following platforms:

  * Debian GNU/Linux jessie
  * Ubuntu 16.04 LTS
  * Ubuntu 16.10
  * CentOS 7

## Package repository

http://packages.groonga.org/ provides packages. You need to enable
the package repository before you install packages.

### Debian GNU/Linux

You add the following apt-lines to
`/etc/apt/sources.list.d/groonga.list`:

```text
deb http://packages.groonga.org/debian/ jessie main
deb-src http://packages.groonga.org/debian/ jessie main
```

Then you run the following command lines:

```text
% sudo apt update
% sudo apt install -y --allow-unauthenticated groonga-keyring
% sudo apt update
```

### Ubuntu

```text
% sudo apt install -y software-properties-common
% sudo add-apt-repository -y ppa:groonga/ppa
% sudo apt update
```

### CentOS 7

```text
% sudo yum install -y http://packages.groonga.org/centos/groonga-release-1.2.0-1.noarch.rpm
```

## Apache Arrow C++

This section describes how to install
[Apache Arrow C++](https://github.com/apache/arrow/tree/master/cpp)
package.

### Debian GNU/Linux

```text
% sudo apt install -y libarrow-dev
```

### Ubuntu

```text
% sudo apt install -y libarrow-dev
```

### CentOS 7

```text
% sudo yum install -y --enablerepo=epel arrow-devel
```

## Apache Arrow GLib (C API)

This section describes how to install
[Apache Arrow GLib](https://github.com/apache/arrow/tree/master/c_glib)
package.

### Debian GNU/Linux

```text
% sudo apt install -y libarrow-glib-dev
```

### Ubuntu

```text
% sudo apt install -y libarrow-glib-dev
```

### CentOS 7

```text
% sudo yum install -y --enablerepo=epel arrow-glib-devel
```

## Apache Parquet C++

This section describes how to install
[Apache Parquet C++](https://github.com/apache/parquet) package.

### Debian GNU/Linux

```text
% sudo apt install -y libparquet-dev
```

### Ubuntu

```text
% sudo apt install -y libparquet-dev
```

### CentOS 7

```text
% sudo yum install -y --enablerepo=epel parquet-devel
```

## License

Apache-2.0

Copyright 2017 Kouhei Sutou \<kou@clear-code.com\>

See LICENSE and NOTICE for details.
