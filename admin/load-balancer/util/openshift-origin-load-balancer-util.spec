%if 0%{?fedora}%{?rhel} <= 6
    %global scl ruby193
    %global scl_prefix ruby193-
%endif
Summary:       OpenShift utilities for load-balancer integration
Name:          openshift-origin-load-balancer-util
Version: 0.6
Release:       1%{?dist}
Group:         Network/Daemons
License:       ASL 2.0
URL:           http://www.openshift.com
Source0:       http://mirror.openshift.com/pub/openshift-origin/source/%{name}/%{name}-%{version}.tar.gz
Requires:      rubygem-openshift-origin-load-balancer-common
Requires:      %{?scl:%scl_prefix}rubygem-daemons
BuildArch:     noarch

%description
This package contains OpenShift utilities for interacting with
a load-balancer.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}%{_sbindir}

cp bin/oo-* bin/openshift-load-balancer-daemon %{buildroot}%{_sbindir}/

%files
%attr(0750,-,-) %{_sbindir}/oo-admin-load-balancer
%attr(0750,-,-) %{_sbindir}/openshift-load-balancer-daemon

%doc LICENSE

%post

%changelog
* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.6-1
- Expose dummy model (miciah.masters@gmail.com)

* Thu Jul 25 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.5-1
- oo-admin-load-balancer: Update for logging changes (miciah.masters@gmail.com)

* Wed Jul 17 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.4-1
- oo-admin-load-balancer: No backtrace for --help (miciah.masters@gmail.com)

* Wed Jul 17 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.3-1
- 

* Wed Jul 17 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.2-1
- Load F5/LBaaS backends conditionally (miciah.masters@gmail.com)

* Tue Jul 09 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.1-1
- new package built with tito

