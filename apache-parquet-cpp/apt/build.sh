#!/bin/sh
# -*- sh-indentation: 2; sh-basic-offset: 2 -*-

LANG=C

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

. /host/env.sh

distribution=$(lsb_release --id --short | tr 'A-Z' 'a-z')
code_name=$(lsb_release --codename --short)
case "${distribution}" in
  debian)
    component=main
    ;;
  ubuntu)
    component=universe
    ;;
esac
specific_debian_dir="debian.${distribution}-${code_name}"

if [ "${DEBUG:-no}" = "yes" ]; then
  apt_options=""
else
  apt_options="-qq"
fi
cat <<APT_LINE > /etc/apt/sources.list.d/red-data-tools.list
deb https://packages.red-data-tools.org/${distribution}/ ${code_name} ${component}
APT_LINE
if [ "${code_name}" = "trusty" ]; then
  apt_update_options=""
else
  apt_update_options="--allow-insecure-repositories"
fi
run apt update ${apt_options} ${apt_update_options}
run apt install ${apt_options} -y -V --allow-unauthenticated \
  red-data-tools-keyring
run apt update ${apt_options}
run apt install ${apt_options} -y -V libarrow-dev

run mkdir -p build
run cp /host/tmp/${PACKAGE}-${VERSION}.tar.gz \
  build/${PACKAGE}_${VERSION}.orig.tar.gz
run cd build
run tar xfz ${PACKAGE}_${VERSION}.orig.tar.gz
run cd ${PACKAGE}-${VERSION}/
if [ -d "/host/tmp/${specific_debian_dir}" ]; then
  run cp -rp "/host/tmp/${specific_debian_dir}" debian
else
  run cp -rp "/host/tmp/debian" debian
fi
# export DEB_BUILD_OPTIONS=noopt
if [ "${DEBUG:-no}" = "yes" ]; then
  run debuild -us -uc
else
  run debuild -us -uc > /dev/null
fi
run cd -

package_initial=$(echo "${PACKAGE}" | sed -e 's/\(.\).*/\1/')
pool_dir="/host/repositories/${distribution}/pool/${code_name}/${component}/${package_initial}/${PACKAGE}"
run mkdir -p "${pool_dir}/"
run cp *.tar.* *.dsc *.deb "${pool_dir}/"
