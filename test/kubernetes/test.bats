#!/usr/bin/env bash

TMP_ZEROTIER_API="http://localhost:4000/api"
TMP_ZEROTIER_TOKEN=""
TMP_ZEROTIER_NETWORK=""
TMP_ZEROTIER_MEMBER=""

zt_get_token() {
    docker exec -u root zu-main cat /app/backend/data/db.json | jq '.users[0].token' | tr '"' ' ' | xargs
}

zt_get_networks() {
    curl -s -X GET -H "Authorization: token $1" $TMP_ZEROTIER_API/network
}

zt_create_network() {
    curl -s -X POST -H "Authorization: token $1" -d '{}' $TMP_ZEROTIER_API/network
}

setup() {
    load '../helpers/bats-support/load'
    load '../helpers/bats-assert/load'
    load '../helpers/bats-file/load'
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/../src:$PATH"
}

setup_file() {
    # Create KinD cluster
    kind create cluster --config=kind.yaml
    # Install and setup Istio
    istioctl install -f istio.yaml -y
    # Wait for Istio to be ready
    while ! curl -I --silent --fail http://localhost:15021/healthz/ready; do
        echo >&2 'Istio down, retrying in 1s...'
        sleep 1
    done
    # Deploy Zerotier Controller
    kubectl create namespace zerotier
    helm install zerotier-controller oci://ghcr.io/jakoberpf/charts/zerotier-controller --version 0.0.8 --values zerotier-controller-values.yaml -n zerotier
    kubectl create secret generic zerotier-admin-credentials --from-literal=username=admin --from-literal=password=admin -n zerotier
    # Wait for Zerotier Controller to be ready
    while ! curl --header 'Host: zerotier.example.com' http://localhost:80; do
        echo >&2 'Zerotier Controller down, retrying in 1s...'
        sleep 1
    done
    # TMP_ZEROTIER_TOKEN=$(zt_get_token)

    # if [ "$(zt_get_networks $TMP_ZEROTIER_TOKEN | xargs)"="[]" ]; then
    #     echo "No networks created, creating new one"
    #     zt_create_network $TMP_ZEROTIER_TOKEN
    #     # zt_get_networks $TMP_ZEROTIER_TOKEN
    # else
    #     echo "There is already a network created"
    # fi

    # TODO join gateway and client to the network
}

@test "should be able to curl gateway" {
    run bash -c "curl -s --header 'Host: example.com' http://localhost:8080 | grep title"
    assert_output --partial '<title>Welcome to the Example Gateway</title>'
}

@test "should be able to curl service-one via the gateway" {
    run bash -c "curl -s --header 'Host: one.example.com' http://localhost:8080 | grep title"
    assert_output --partial '<title>Welcome to Service One</title>'
}

@test "should be able to curl service-two via the gateway" {
    run bash -c "curl -s --header 'Host: two.example.com' http://localhost:8080 | grep title"
    assert_output --partial '<title>Welcome to Service Two</title>'
}

# teardown_file() {
#     kind delete cluster
# }
