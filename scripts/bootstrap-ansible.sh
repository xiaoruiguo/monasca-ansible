#!/usr/bin/env bash
# Copyright 2014, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# (c) 2014, Kevin Carter <kevin.carter@rackspace.com>

## Shell Opts ----------------------------------------------------------------
set -e -u -x


## Vars ----------------------------------------------------------------------
export HTTP_PROXY=${HTTP_PROXY:-""}
export HTTPS_PROXY=${HTTPS_PROXY:-""}
export ANSIBLE_GIT_RELEASE=${ANSIBLE_GIT_RELEASE:-"v2.1.0.0-1"}
export ANSIBLE_GIT_REPO=${ANSIBLE_GIT_REPO:-"https://github.com/ansible/ansible"}
export ANSIBLE_WORKING_DIR=${ANSIBLE_WORKING_DIR:-/opt/ansible_${ANSIBLE_GIT_RELEASE}}
export SSH_DIR=${SSH_DIR:-"/root/.ssh"}
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-"noninteractive"}
# Set the role fetch mode to any option [galaxy, git-clone]
export ANSIBLE_ROLE_FETCH_MODE=${ANSIBLE_ROLE_FETCH_MODE:-galaxy}

## Functions -----------------------------------------------------------------
info_block "Checking for required libraries." 2> /dev/null ||
    source $(dirname ${0})/scripts-library.sh ||
    source scripts/scripts-library.sh

## Main ----------------------------------------------------------------------
info_block "Bootstrapping System with Ansible"

# Create the ssh dir if needed
ssh_key_create

# Install the base packages
if [[ $HOST_DISTRO =~ ^(Ubuntu|Debian) ]]; then
    apt-get update && apt-get -y install git python-all python-dev curl python2.7-dev build-essential libssl-dev libffi-dev < /dev/null
elif [[ $HOST_DISTRO =~ ^(CentOS|Red Hat) ]]; then
    yum check-update && yum -y install git python2 curl autoconf gcc-c++ python2-devel gcc libffi-devel openssl-devel
elif [[ $HOST_DISTRO =~ ^Fedora ]]; then
    dnf -y install git python curl autoconf gcc-c++ python-devel gcc libffi-devel openssl-devel
fi

# If the working directory exists remove it
if [ -d "${ANSIBLE_WORKING_DIR}" ];then
    rm -rf "${ANSIBLE_WORKING_DIR}"
fi

# Clone down the base ansible source
git clone "${ANSIBLE_GIT_REPO}" "${ANSIBLE_WORKING_DIR}"
pushd "${ANSIBLE_WORKING_DIR}"
    git checkout "${ANSIBLE_GIT_RELEASE}"
    git submodule update --init --recursive
popd


# Install pip
get_pip

# Ensure we use the HTTPS/HTTP proxy with pip if it is specified
PIP_OPTS=""
if [ -n "$HTTPS_PROXY" ]; then
  PIP_OPTS="--proxy $HTTPS_PROXY"
elif [ -n "$HTTP_PROXY" ]; then
  PIP_OPTS="--proxy $HTTP_PROXY"
fi

PIP_COMMAND=pip2
if [ ! $(which "$PIP_COMMAND") ]; then
  PIP_COMMAND=pip
fi

# When upgrading there will already be a pip.conf file locking pip down to the repo server, in such cases it may be
# necessary to use --isolated because the repo server does not meet the specified requirements.
$PIP_COMMAND install $PIP_OPTS -r requirements.txt || $PIP_COMMAND install --isolated $PIP_OPTS -r requirements.txt

# Create a Virtualenv for the Ansible runtime
PYTHON_EXEC_PATH="$(which python2 || which python)"
virtualenv --always-copy --system-site-packages --python="${PYTHON_EXEC_PATH}" /opt/ansible-runtime

# Install ansible
PIP_OPTS+=" --upgrade"
PIP_COMMAND="/opt/ansible-runtime/bin/pip"
# When upgrading there will already be a pip.conf file locking pip down to the repo server, in such cases it may be
# necessary to use --isolated because the repo server does not meet the specified requirements.
$PIP_COMMAND install $PIP_OPTS -r requirements.txt "${ANSIBLE_WORKING_DIR}" || $PIP_COMMAND install --isolated $PIP_OPTS "${ANSIBLE_WORKING_DIR}"

# Link the venv installation of Ansible to the local path
pushd /usr/local/bin
    find /opt/ansible-runtime/bin/ -name 'ansible*' -exec ln -sf {} \;
popd

echo "System is bootstrapped and ready for use."
