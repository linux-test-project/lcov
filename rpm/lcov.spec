Summary: A graphical code coverage front-end
Name: lcov
Version: 1.16
Release: 1
License: GPLv2+
Group: Development/Tools
URL: https://github.com/linux-test-project/lcov
Source0: https://github.com/linux-test-project/%{name}/releases/download/v%{version}/%{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root
BuildArch: noarch
Requires: perl >= 5.8.8
Prefix: /usr
Prefix: /etc

%description
LCOV is a set of command line tools that can be used to collect, process, and
visualize code coverage data in an easy-to-use way. It aims to be suitable for
projects of a wide range of sizes, with particular focus on deployment in
automated CI/CD systems and large projects implemented using multiple languages.

LCOV works with existing environment-specific profiling mechanisms including,
but not limited to, the gcov tool that is part of the GNU Compiler Collection
(GCC).

%prep
%setup -q -n %{name}-%{version}

%build
exit 0

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT PREFIX=/usr CFG_DIR=/etc

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
/usr/bin/*
/usr/lib/*
/usr/share/man/man*/*
/usr/share/lcov/support-scripts/*
%config /etc/*

%changelog
* Mon Aug 22 2016 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- updated "make install" call to work with PREFIX Makefile changes

* Mon May 07 2012 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- added dependency on perl 5.8.8 for >>& open mode support

* Wed Aug 13 2008 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- changed description + summary text

* Mon Aug 20 2007 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- fixed "Copyright" tag

* Mon Jul 14 2003 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- removed variables for version/release to support source rpm building
- added initial rm command in install section

* Mon Apr 7 2003 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- implemented variables for version/release

* Fri Oct 18 2002 Peter Oberparleiter (Peter.Oberparleiter@de.ibm.com)
- created initial spec file
