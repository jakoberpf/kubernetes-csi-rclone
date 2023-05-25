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
    # Build CSI Controller image and load into cluster
    make
    kind load docker-image jakoberpf/csi-rclone:ci --name "$KIND_CLUSTER_NAME"
    # Deploy CSI Controller, Storage Class and Storage Plugin
    kubectl apply -f deploy/kubernetes/1.19
    # Wait for CSI Controller to be ready
    while "$(kubectl get sts csi-controller-rclone -n kube-system -o yaml | yq '.status.replicas')" != "$(kubectl get sts csi-controller-rclone -n kube-system -o yaml | yq '.status.readyReplicas')"; do
        echo >&2 'CSI Controller down, retrying in 1s...'
        ((c++)) && ((c==60)) && exit 0
        sleep 1
    done
}

@test "should have a rclone StorageClass" {
    run bash -c "kubectl get storageclass -o yaml | yq '.items[].metadata.name'"
    assert_output --partial 'rclone'
}

@test "should not be the default StorageClass" {
    run bash -c "kubectl describe storageclass rclone"
    assert_output --partial 'IsDefaultClass:  No'
}

#@test "should be able to mount dropbox with global secret" {
#    kubectl apply -f test/secret-dropbox.yaml -n kube-system
#    kubectl apply -f test/pv.yaml -n kube-system
#    kubectl apply -f test/pvc.yaml -n kube-system
#    kubectl apply -f test/pod.yaml -n kube-system
#    run bash -c "kubectl describe storageclass rclone"
#    assert_output --partial 'IsDefaultClass:  No'
#}

@test "should be able to mount dropbox with pv attributes" {
    kubectl apply -f test/pv-dropbox.yaml -n kube-system
    kubectl apply -f test/pvc.yaml -n kube-system
    kubectl apply -f test/pod.yaml -n kube-system
    # Wait until producer pod is ready
    kubectl wait --for=condition=Ready pod/nginx-example -n kube-system
    run bash -c "kubectl describe storageclass rclone"
    assert_output --partial 'IsDefaultClass:  No'
}

# teardown_file() {
#     kind delete cluster --name "$KIND_CLUSTER_NAME"
# }
