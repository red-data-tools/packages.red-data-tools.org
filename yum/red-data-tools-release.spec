Summary: Red Data Tools release files
Name: red-data-tools-release
Version: 1.0.0
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

%{__install} -Dp -m0644 RPM-GPG-KEY-red-data-tools %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-red-data-tools

%{__install} -Dp -m0644 red-data-tools.repo %{buildroot}%{_sysconfdir}/yum.repos.d/red-data-tools.repo

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root, 0755)
%doc *
%pubkey RPM-GPG-KEY-red-data-tools
%dir %{_sysconfdir}/yum.repos.d/
%config(noreplace) %{_sysconfdir}/yum.repos.d/red-data-tools.repo
%dir %{_sysconfdir}/pki/rpm-gpg/
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-red-data-tools

%changelog
* Fri Sep 29 2017 Kouhei Sutou <kou@clear-code.com> - 1.0.0-1
- Initial release.
