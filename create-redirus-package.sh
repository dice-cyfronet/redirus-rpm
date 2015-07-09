#!/bin/bash

function log_shell
{
    printf "$1... "
    output=$($2 2>&1)
    output_exitcode=$?
    if [[ $output_exitcode == 0 ]]; then
        printf "\033[32msucceed\033[0m\n"
        printf " ------------\n"
        echo "${output}"
        printf " ------------\n"
    else
        printf "\033[31mfailed\033[0m\n"
        printf " ------------\n"
        echo "${output}"
        printf " ------------\n"
        exit $output_exitcode
    fi
}

function create_directories
{
    __id=$(id -u)
    mkdir -p ${__dir}/build-redirus-${__version}/{BUILD,RPMS,SOURCES,SPECS,SRPMS,tmp}
    [ -d /opt/redirus ] || sudo mkdir -p /opt/redirus
    [ "$(stat --format=\"%u\" /opt/redirus/)" == "${__id}" ] || sudo chown -R ${__id}:${__id} /opt/redirus
    exit $?
}

function create_rpmmacros
{
    cat <<EOF > ~/.rpmmacros
%packager ${__packager}
%_topdir ${__dir}/build-redirus-${__version}
%_tmppath ${__dir}/build-redirus-${__version}/tmp
EOF
    exit $?
}

function create_spec
{
    cat <<EOF > ${__dir}/build-redirus-${__version}/SPECS/redirus.spec
Name: redirus
Version: ${__version}
Release: 0
Epoch: ${__serial}

License: MIT
URL: https://github.com/dice-cyfronet/redirus
Summary: Redirus

Group: Redirus
BuildArch: x86_64

Requires: libcap nginx

BuildRequires: epel-release ruby ruby(rubygems) autoconf bison gcc gcc-c++ make openssl-devel libyaml-devel readline-devel zlib-devel pcre pcre-devel libcap

%description
Redirus software.

##
# Preinstall script.
##
%pre
function log_shell
{
    printf "\$1... "
    output=\$(bash -c "\$2" 2>&1)

    if [[ \$? == 0 ]]; then
        printf "\033[32msucceed\033[0m\n"
    else
        printf "\033[31mfailed\033[0m\n------------\n\${output}\n------------\n"
        exit 1
    fi
}

echo "Run before installation frodm the new package."

log_shell "Create 'redirus' user (if does not exist)" \
            "id -u redirus &>/dev/null || adduser --home-dir /opt/redirus --system redirus"

##
# Postinstall script.
##
%post
function log_shell
{
    printf "\$1... "
    output=\$(bash -c "\$2" 2>&1)

    if [[ \$? == 0 ]]; then
        printf "\033[32msucceed\033[0m\n"
    else
        printf "\033[31mfailed\033[0m\n------------\n\${output}\n------------\n"
        exit 1
    fi
}

echo "Run after installation from the new package."

echo "Link redirus binaries"

pushd /usr/bin 
    ln -s /opt/redirus/bin/redirus redirus 
    ln -s /opt/redirus/bin/redirus-init redirus-init 
    ln -s /opt/redirus/bin/redirus-client redirus-client 
popd

echo  "Link systemd configuration files."

pushd /usr/lib/systemd/system
    ln -s /opt/redirus/resources/nginx-redirus.service nginx-redirus.service
    ln -s /opt/redirus/resources/redirus.service redirus.service
popd 

echo  "Setting capabilities to allow nginx to bind to low-numbered ports."

setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx

log_shell "Enable 'redirus' service" \
            "systemctl enable redirus.service"

##
# Preuninstall script.
##
%preun
function log_shell
{
    printf "\$1... "
    output=\$(bash -c "\$2" 2>&1)

    if [[ \$? == 0 ]]; then
        printf "\033[32msucceed\033[0m\n"
:q
    else
        printf "\033[31mfailed\033[0m\n------------\n\${output}\n------------\n"
        exit 1
    fi
}

echo "Run before uninstallation from the old package."

##
# Postuninstall script.
##
%postun
function log_shell
{
    printf "\$1... "
    output=\$(bash -c "\$2" 2>&1)

    if [[ \$? == 0 ]]; then
        printf "\033[32msucceed\033[0m\n"
    else
        printf "\033[31mfailed\033[0m\n------------\n\${output}\n------------\n"
        exit 1
    fi
}

echo "Run after uninstallation from the old package."

##
# Prepbuild script.
##
%prep
echo "Run to prepare the package for building."

if [ ! -d "ruby-2.1.3" ]
then
    echo "Prepare ruby environment."
    wget http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.3.tar.gz
    tar zxvf ruby-2.1.3.tar.gz
fi

pushd ruby-2.1.3
    ./configure --prefix=/opt/redirus/ruby --disable-install-rdoc
    make
    make install
popd

gem fetch redirus -v 0.2.1

git clone https://github.com/dice-cyfronet/redirus-rpm.git

##
# Build script.
##
%build
echo "Run to build the package."
PATH=/opt/redirus/ruby/bin:\${PATH}

echo "Install redirus gem."
gem install --no-rdoc --no-ri --install-dir /opt/redirus/ruby/lib/ruby/gems/2.1.0 --bindir bin --force redirus-0.2.1.gem 

##
# Install script.
##
%install
echo "Run to install the built files."

echo "Copy application and ruby files."
rm -rf \${RPM_BUILD_ROOT}/opt

mkdir -p \${RPM_BUILD_ROOT}/opt/redirus
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/bin
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/ruby
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/resources
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/resources/configurations
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/resources/log 
mkdir -p \${RPM_BUILD_ROOT}/opt/redirus/resources/tmp

cp -r %{_builddir}/bin/* \${RPM_BUILD_ROOT}/opt/redirus/bin
cp -r %{_builddir}/redirus-rpm/resources/* \${RPM_BUILD_ROOT}/opt/redirus/resources 
cp -r /opt/redirus/ruby/* \${RPM_BUILD_ROOT}/opt/redirus/ruby

%files
%defattr(755, redirus, redirus, 755)
%dir /opt/redirus
/opt/redirus/*

%clean
#rm -rf \${RPM_BUILD_ROOT}
EOF
    exit $?
}

function install_required_packages
{
    packages=$(grep BuildRequires ${__dir}/build-redirus-${__version}/SPECS/redirus.spec | sed 's/BuildRequires\:\s//g')
    sudo yum install -y ${packages}
}

function build_rpm
{
    pushd ${__dir}/build-redirus-${__version} > /dev/null 2>&1
        rpmbuild -ba ${__dir}/build-redirus-${__version}/SPECS/redirus.spec
        output_exitcode=$?
    popd > /dev/null 2>&1
    exit $output_exitcode
}

function create_repo
{
    pushd ${__dir} > /dev/null 2>&1
        rm -f ${__dir}/*.rpm
        find ${__dir}/ -name *.rpm -exec cp {} ${__dir}/ \;
        rm -f repo-redirus.tar.gz
        mkdir -p ${__dir}/repo-redirus-${__serial}/redirus/x86_64/
        mv *.rpm ${__dir}/repo-redirus-${__serial}/redirus/x86_64/
        createrepo ${__dir}/repo-redirus-${__serial}/redirus/x86_64/
        createrepo ${__dir}/repo-redirus-${__serial}/redirus/
        tar zcvf ${__dir}/repo-redirus-${__serial}.tar.gz repo-redirus-${__serial}/
        rm -rf ${__dir}/repo-redirus-${__serial}/
    popd
    exit 0
}

__dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

command -v rpmbuild > /dev/null 2>&1 || { echo "No 'rpm-build'" >&2; log_shell "Install rpm-build tools" "sudo yum install -y rpm-build"; }
command -v createrepo > /dev/null 2>&1 || { echo "No 'createrepo'" >&2; log_shell "Install createrepo tools" "sudo yum install -y createrepo"; }

__packager=b.wilk@cyfronet.pl
__serial=$(date +%s)
__version=latest

log_shell "Create directories to packaging" "create_directories"
log_shell "Create rpm macro" "create_rpmmacros"
log_shell "Create spec file" "create_spec"
log_shell "Install build required packages" "install_required_packages"
log_shell "Build RPM packages" "build_rpm"
log_shell "Create repo with packages" "create_repo"
