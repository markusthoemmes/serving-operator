#!/usr/bin/env bash

# Copyright 2019 The Knative Authors
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

# This script provides helper methods to perform cluster actions.
source $(dirname $0)/../vendor/knative.dev/test-infra/scripts/e2e-tests.sh

# Latest serving operator release.
readonly LATEST_SERVING_OPERATOR_RELEASE_VERSION="v0.12.2"
# Latest serving release. This can be different from LATEST_SERVING_OPERATOR_RELEASE_VERSION.
LATEST_SERVING_RELEASE_VERSION="v0.12.1"
# Istio version we test with
readonly ISTIO_VERSION="1.4-latest"
# Test without Istio mesh enabled
readonly ISTIO_MESH=0
# Namespace used for tests
readonly TEST_NAMESPACE="knative-serving"

OPERATOR_DIR=$(dirname $0)/..
KNATIVE_SERVING_DIR=${OPERATOR_DIR}/..
release_yaml="$(mktemp)"

# Choose a correct istio-crds.yaml file.
# - $1 specifies Istio version.
function istio_crds_yaml() {
  local istio_version="$1"
  echo "third_party/${istio_version}/istio-crds.yaml"
}

# Choose a correct istio.yaml file.
# - $1 specifies Istio version.
# - $2 specifies whether we should use mesh.
function istio_yaml() {
  local istio_version="$1"
  local istio_mesh=$2
  local suffix=""
  if [[ $istio_mesh -eq 0 ]]; then
    suffix="ci-no-mesh"
  else
    suffix="ci-mesh"
  fi
  echo "third_party/${istio_version}/istio-${suffix}.yaml"
}

# Download the repository of Knative Serving. The purpose of this function is to download the source code of serving
# and retrive the LATEST_SERVING_RELEASE_VERSION for further use.
# Parameter: $1 - branch of the repository.
function donwload_knative_serving() {
  # Go the directory to download the source code of knative serving
  cd ${KNATIVE_SERVING_DIR}
  # Download the source code of knative serving
  git clone https://github.com/knative/serving.git
  cd serving
  local branch=$1
  if [ -n "${branch}" ] ; then
    git fetch origin ${branch}:${branch}
    git checkout ${branch}
  fi
  cd ${OPERATOR_DIR}
}

# Install Istio.
function install_istio() {
  local base_url="https://raw.githubusercontent.com/knative/serving/${LATEST_SERVING_RELEASE_VERSION}"
  local istio_version="istio-${ISTIO_VERSION}"
  if [[ ${istio_version} == *-latest ]] ; then
    istio_version=$(curl https://raw.githubusercontent.com/knative/serving/${LATEST_SERVING_RELEASE_VERSION}/third_party/${istio_version})
  fi
  INSTALL_ISTIO_CRD_YAML="${base_url}/$(istio_crds_yaml $istio_version)"
  INSTALL_ISTIO_YAML="${base_url}/$(istio_yaml $istio_version $ISTIO_MESH)"

  echo ">> Installing Istio"
  echo "Istio CRD YAML: ${INSTALL_ISTIO_CRD_YAML}"
  echo "Istio YAML: ${INSTALL_ISTIO_YAML}"

  echo ">> Bringing up Istio"
  echo ">> Running Istio CRD installer"
  kubectl apply -f "${INSTALL_ISTIO_CRD_YAML}" || return 1
  wait_until_batch_job_complete istio-system || return 1

  echo ">> Running Istio"
  kubectl apply -f "${INSTALL_ISTIO_YAML}" || return 1
}

function create_namespace() {
  echo ">> Creating test namespaces"
  # All the custom resources and Knative Serving resources are created under this TEST_NAMESPACE.
  kubectl create namespace $TEST_NAMESPACE
}

function install_serving_operator() {
  cd ${OPERATOR_DIR}
  header "Installing Knative Serving operator"
  # Deploy the operator
  ko apply -f config/
  wait_until_pods_running default || fail_test "Serving Operator did not come up"
}

# Uninstalls Knative Serving from the current cluster.
function knative_teardown() {
  echo ">> Uninstalling Knative serving"
  echo "Istio YAML: ${INSTALL_ISTIO_YAML}"
  echo ">> Bringing down Serving"
  kubectl delete -n $TEST_NAMESPACE KnativeServing --all
  echo ">> Bringing down Istio"
  kubectl delete --ignore-not-found=true -f "${INSTALL_ISTIO_YAML}" || return 1
  kubectl delete --ignore-not-found=true clusterrolebinding cluster-admin-binding
  echo ">> Bringing down Serving Operator"
  ko delete --ignore-not-found=true -f config/ || return 1
  echo ">> Removing test namespaces"
  kubectl delete all --all --ignore-not-found --now --timeout 60s -n $TEST_NAMESPACE
  kubectl delete --ignore-not-found --now --timeout 300s namespace $TEST_NAMESPACE
}
