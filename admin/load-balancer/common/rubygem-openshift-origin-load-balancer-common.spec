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
Version: 0.31
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
* Wed Sep 04 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.31-1
- controllers/lbaas.rb: Fix delete_monitor (miciah.masters@gmail.com)
- controllers/lbaas.rb: Lazily load pools etc. (miciah.masters@gmail.com)

* Wed Sep 04 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.30-1
- controllers/lbaas.rb: Fix delete_monitor operation (miciah.masters@gmail.com)

* Wed Sep 04 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.29-1
- Make attributes more consistent in controllers (miciah.masters@gmail.com)

* Fri Aug 16 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.28-1
- models/lbaas.rb: Fix iRules template (miciah.masters@gmail.com)

* Mon Aug 12 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.27-1
- Make monitor timeout configurable (miciah.masters@gmail.com)

* Mon Aug 05 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.26-1
- Make monitor interval configurable (miciah.masters@gmail.com)
- Make monitor type configurable (miciah.masters@gmail.com)

* Thu Aug 01 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.25-1
- Make monitor up code configurable (miciah.masters@gmail.com)

* Tue Jul 30 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.24-1
- Make pool and route names configurable (miciah.masters@gmail.com)

* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.23-1
- models/dummy.rb Fix delete_pool_members (miciah.masters@gmail.com)

* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.22-1
- laod-balancer.conf: Fix default LOGFILE setting (miciah.masters@gmail.com)

* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.21-1
- controllers/f5.rb: Don't require f5-icontrol (miciah.masters@gmail.com)

* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.20-1
- models/dummy.rb: require models/load_balancer (miciah.masters@gmail.com)

* Mon Jul 29 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.19-1
- Expose dummy model (miciah.masters@gmail.com)

* Fri Jul 26 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.18-1
- models/lbaas.rb: Fix escaping in iRule (miciah.masters@gmail.com)

* Thu Jul 25 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.17-1
- models/lbaas.rb: Fix iRules template (miciah.masters@gmail.com)

* Wed Jul 24 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.16-1
- Fix backtrace logging output (miciah.masters@gmail.com)
- models/lbaas.rb: Missing change from last commit (miciah.masters@gmail.com)

* Wed Jul 24 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.15-1
- Use Logger for output (miciah.masters@gmail.com)
- Make model initialize methods more consistent (miciah.masters@gmail.com)
- controllers/lbaas.rb: Fix grammar in a comment (miciah.masters@gmail.com)
- controllers/lbaas.rb: More verbosity in initialize (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.14-1
- controllers/lbaas.rb: Fix another typo (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.13-1
- models/lbaas.rb: Fix timeouts (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.12-1
- controllers/lbaas.rb: Don't reap a cancelled op (miciah.masters@gmail.com)
- Fix typo in last commit (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.11-1
- LBaaS: re-authenticate when the token expires (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.10-1
- controllers/lbaas.rb: Improve Operation logging (miciah.masters@gmail.com)
- load-balancer.conf: Increase timeouts to 5 mins (miciah.masters@gmail.com)

* Tue Jul 23 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.9-1
- Add LBAAS_TIMEOUT and LBAAS_OPEN_TIMEOUT (miciah.masters@gmail.com)
- models/lbaas.rb: Refactor REST Calls (miciah.masters@gmail.com)
- models/lbaas.rb: Fix authentication logging (miciah.masters@gmail.com)
- controllers/lbaas.rb: Fix polling logging (miciah.masters@gmail.com)
- models/lbaas.rb: Remove dead code (miciah.masters@gmail.com)

* Mon Jul 22 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.8-1
- Fix embarrassing typo in last commit (miciah.masters@gmail.com)

* Mon Jul 22 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.7-1
- models/lbaas.rb: More verbose authentication (miciah.masters@gmail.com)
- controllers/lbaas.rb: Fix typo in logging output (miciah.masters@gmail.com)

* Fri Jul 19 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.6-1
- controllers/lbaas.rb: Combine add/remove ops (miciah.masters@gmail.com)
- controllers/lbaas.rb: Print details when job fails (miciah.masters@gmail.com)
- controllers/lbaas.rb: Print polling status (miciah.masters@gmail.com)

* Thu Jul 18 2013 Miciah Dashiel Butler Masters <mmasters@redhat.com> 0.5-1
- Bump version number

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

