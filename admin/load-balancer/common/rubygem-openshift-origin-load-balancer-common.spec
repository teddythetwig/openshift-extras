%if 0%{?fedora}%{?rhel} <= 6
    %global scl ruby193
    %global scl_prefix ruby193-
%endif
%{!?scl:%global pkg_name %{name}}
%{?scl:%scl_package rubygem-%{gem_name}}
%global gem_name openshift-origin-load-balancer-common
%global rubyabi 1.9.1
%global appdir %{_var}/lib/openshift
%global apprundir %{_var}/run/openshift

Summary:       OpenShift common code for load balancer integration
Name:          rubygem-%{gem_name}
Version: 0.4
Release:       1%{?dist}
Group:         Development/Languages
License:       ASL 2.0
URL:           http://openshift.redhat.com
Source0:       http://mirror.openshift.com/pub/openshift-origin/source/%{name}/rubygem-%{gem_name}-%{version}.tar.gz
%if 0%{?fedora} >= 19
Requires:      ruby(release)
%else
Requires:      %{?scl:%scl_prefix}ruby(abi) >= %{rubyabi}
%endif
Requires:      %{?scl:%scl_prefix}rubygems
Requires:      %{?scl:%scl_prefix}rubygem(json)
Requires:      %{?scl:%scl_prefix}rubygem(parseconfig)
%if 0%{?fedora}%{?rhel} <= 6
BuildRequires: %{?scl:%scl_prefix}build
BuildRequires: scl-utils-build
%endif
%if 0%{?fedora} >= 19
BuildRequires: ruby(release)
%else
BuildRequires: %{?scl:%scl_prefix}ruby(abi) >= %{rubyabi}
%endif
BuildRequires: %{?scl:%scl_prefix}rubygems
BuildRequires: %{?scl:%scl_prefix}rubygems-devel
BuildArch:     noarch

%description
OpenShift common library code for load balancer integration.

%prep
%setup -q

%build
%{?scl:scl enable %scl - << \EOF}
mkdir -p .%{gem_dir}
gem build %{gem_name}.gemspec
gem install -V \
        --local \
        --install-dir ./%{gem_dir} \
        --bindir ./%{_bindir} \
        --force %{gem_name}-%{version}.gem
%{?scl:EOF}

%install
mkdir -p %{buildroot}%{gem_dir}
cp -a ./%{gem_dir}/* %{buildroot}%{gem_dir}/

mkdir -p %{buildroot}/etc/openshift
mv %{buildroot}%{gem_instdir}/conf/* %{buildroot}/etc/openshift

%files
%dir %{gem_instdir}
%dir %{gem_dir}
%doc Gemfile LICENSE
%{gem_dir}/doc/%{gem_name}-%{version}
%{gem_dir}/gems/%{gem_name}-%{version}
%{gem_dir}/cache/%{gem_name}-%{version}.gem
%{gem_dir}/specifications/%{gem_name}-%{version}.gemspec
%config(noreplace) /etc/openshift/load-balancer.conf

%changelog
* Thu Jul 18 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.4-1
- Rewrite LBaaS keystone authentication (miciah.masters@gmail.com)
- models/lbaas.rb: Better error handling in auth (miciah.masters@gmail.com)
- models/lbaas.rb: Rename tenant to tenantname (miciah.masters@gmail.com)
- Add LBAAS_KEYSTONE_HOST to default conf (miciah.masters@gmail.com)

* Tue Jul 09 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.3-1
- new package built with tito

* Fri May 31 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.2-1
- 

* Fri May 31 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.1-1
- new package built with tito

