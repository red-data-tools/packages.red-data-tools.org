Summary: Red Data Tools release files
Name: red-data-tools-release
Version: 1.0.1
Release: 1
License: ASL-2.0
URL: https://packages.red-data-tools.org/
Source: red-data-tools-release.tar.gz
Group: System Environment/Base
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-%(%{__id_u} -n)
BuildArchitectures: noarch
Requires: epel-release

%description
Red Data Tools release files

%prep
%setup -c

%build

%install
%{__rm} -rf %{buildroot}

%{__install} -Dp -t %{buildroot}%{_sysconfdir}/pki/rpm-gpg/ -m0644 RPM-GPG-KEY-*

%{__install} -Dp -m0644 red-data-tools.repo %{buildroot}%{_sysconfdir}/yum.repos.d/red-data-tools.repo

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root, 0755)
%doc *
%pubkey RPM-GPG-KEY-f72898cb
%dir %{_sysconfdir}/yum.repos.d/
%config(noreplace) %{_sysconfdir}/yum.repos.d/red-data-tools.repo
%dir %{_sysconfdir}/pki/rpm-gpg/
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-*

%post
if grep -q 'Amazon Linux release 2' /etc/system-release 2>/dev/null; then
  yum-config-manager --disable red-data-tools-centos
  yum-config-manager --enable red-data-tools-linux
else
  yum-config-manager --disable red-data-tools-amazon-linux
  yum-config-manager --enable red-data-tools-centos
fi

%changelog
* Fri Sep 6 2019 Kouhei Sutou <kou@clear-code.com> - 1.0.1-1
- Add support for Amazon Linux 2.

* Fri Sep 29 2017 Kouhei Sutou <kou@clear-code.com> - 1.0.0-1
- Initial release.
