#!/usr/bin/env bash

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT" || exit

KIND_CLUSTER_NAME=$(yq '.name' < "$GIT_ROOT"/test/kind.yaml)

setup() {
    load './helpers/bats-support/load'
    load './helpers/bats-assert/load'
    load './helpers/bats-file/load'
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/../src:$PATH"
}

setup_file() {
    # Create KinD cluster
    if [[ "$(kind get clusters)" != *"$KIND_CLUSTER_NAME"* ]]; then
        kind create cluster --config="$GIT_ROOT"/test/kind.yaml
    fi
    # Deploy Minio
    # helm repo add minio https://charts.min.io/
    helm upgrade --install --create-namespace --namespace minio minio minio/minio --version 5.0.9 \
      --set resources.requests.memory=512Mi \
      --set persistence.enabled=false \
      --set mode=standalone \
      --set replicas=1 \
      --set rootPassword=SECRET_ACCESS_KEY \
      --set rootUser=ACCESS_KEY_ID
    # Build CSI Controller image and load into cluster
    make
    kind load docker-image jakoberpf/csi-rclone:ci --name "$KIND_CLUSTER_NAME"
    # Deploy CSI Controller, Storage Class and Storage Plugin
    kubectl apply -f deploy/kubernetes/1.19

    kubectl apply -f test/secret-minio.yaml -n kube-system
    kubectl apply -f test/pv.yaml -n kube-system
    kubectl apply -f test/pvc.yaml -n kube-system
    kubectl apply -f test/busybox.yaml -n kube-system
}

@test "should have a rclone StorageClass" {
    run bash -c "kubectl get storageclass -o yaml | yq '.items[].metadata.name'"
    assert_output --partial 'rclone'
}

@test "should not be the default StorageClass" {
    run bash -c "kubectl describe storageclass rclone"
    assert_output --partial 'IsDefaultClass:  No'
}

# teardown_file() {
#     kind delete cluster --name "$KIND_CLUSTER_NAME"
# }