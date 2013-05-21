Summary:       OpenShift utilities for load-balancer integration
Name:          openshift-origin-load-balancer-util
Version: 0.0
Release:       1%{?dist}
Group:         Network/Daemons
License:       ASL 2.0
URL:           http://www.openshift.com
Source0:       http://mirror.openshift.com/pub/openshift-origin/source/%{name}/%{name}-%{version}.tar.gz
Requires:      rubygem-openshift-origin-load-balancer-common
BuildArch:     noarch

%description
This package contains OpenShift utilities for interacting with
a load-balancer.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}%{_sbindir}

cp bin/oo-* %{buildroot}%{_sbindir}/

%files
%attr(0750,-,-) %{_sbindir}/oo-admin-load-balancer

%doc LICENSE

%post

%changelog
