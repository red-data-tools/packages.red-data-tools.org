#!/bin/sh
# -*- sh-indentation: 2; sh-basic-offset: 2 -*-

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

rpmbuild_options=

. /host/env.sh

distribution=$(cut -d " " -f 1 /etc/redhat-release | tr "A-Z" "a-z")
if grep -q Linux /etc/redhat-release; then
  distribution_version=$(cut -d " " -f 4 /etc/redhat-release)
else
  distribution_version=$(cut -d " " -f 3 /etc/redhat-release)
fi
distribution_version=$(echo ${distribution_version} | sed -e 's/\..*$//g')

architecture="$(arch)"
case "${architecture}" in
  i*86)
    architecture=i386
    ;;
esac


if [ "${DEBUG:-no}" = "yes" ]; then
  yum_options=""
else
  yum_options="--quiet"
fi

release_rpm=red-data-tools-release-1.0.0-1.noarch.rpm
run yum install -y ${yum_options} \
    https://packages.red-data-tools.org/${distribution}/${release_rpm}
run yum install -y arrow-devel


if [ -x /usr/bin/rpmdev-setuptree ]; then
  rm -rf .rpmmacros
  run rpmdev-setuptree
else
  run cat <<EOM > ~/.rpmmacros
%_topdir ${HOME}/rpmbuild
EOM
  run mkdir -p ~/rpmbuild/SOURCES
  run mkdir -p ~/rpmbuild/SPECS
  run mkdir -p ~/rpmbuild/BUILD
  run mkdir -p ~/rpmbuild/RPMS
  run mkdir -p ~/rpmbuild/SRPMS
fi

repository="/host/repositories/${distribution}/${distribution_version}"
rpm_dir="${repository}/${architecture}/Packages"
srpm_dir="${repository}/source/SRPMS"
run mkdir -p "${rpm_dir}" "${srpm_dir}"

# for debug
# rpmbuild_options="$rpmbuild_options --define 'optflags -O0 -g3'"

cd

if [ -n "${SOURCE_ARCHIVE}" ]; then
  run cp /host/tmp/${SOURCE_ARCHIVE} rpmbuild/SOURCES/
else
  run cp /host/tmp/${PACKAGE}-${VERSION}.* rpmbuild/SOURCES/
fi
run cp \
    /host/tmp/${distribution}/${PACKAGE}.spec \
    rpmbuild/SPECS/

cat <<BUILD > build.sh
#!/bin/bash

rpmbuild -ba ${rpmbuild_options} rpmbuild/SPECS/${PACKAGE}.spec
BUILD
run chmod +x build.sh
if [ "${distribution_version}" = 6 ]; then
  if [ "${DEBUG:-no}" = "yes" ]; then
    run scl enable devtoolset-6 ./build.sh
  else
    run scl enable devtoolset-6 ./build.sh > /dev/null
  fi
else
  if [ "${DEBUG:-no}" = "yes" ]; then
    run ./build.sh
  else
    run ./build.sh > /dev/null
  fi
fi

run mv rpmbuild/RPMS/*/* "${rpm_dir}/"
run mv rpmbuild/SRPMS/* "${srpm_dir}/"
