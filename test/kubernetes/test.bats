#!/usr/bin/env bash

ZEROTIER_TEST_API="http://localhost/api"
ZEROTIER_TEST_API_HOST="zerotier.example.com"

zt_get_token() {
    uiPodName=$(kubectl get pods -n zerotier -o json | jq '.items[] | select(.metadata.labels.component=="ui") | .metadata.name' | xargs)
    kubectl exec $uiPodName -n zerotier -- cat /app/backend/data/db.json |  jq '.users[0].token' | tr '"' ' ' | xargs
}

zt_get_networks() {
    curl -s -X GET -H "Authorization: token $1" --header "Host: $ZEROTIER_TEST_API_HOST" $ZEROTIER_TEST_API/network
}

zt_create_network() {
    curl -s -X POST -H "Authorization: token $1" -d '{}' --header "Host: $ZEROTIER_TEST_API_HOST" $ZEROTIER_TEST_API/network
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
    while ! curl --header 'Host: zerotier.example.com' http://localhost/app/; do
        echo >&2 'Zerotier Controller down, retrying in 1s...'
        sleep 1
    done
    # Get Zerotier Controller API token
    TMP_ZEROTIER_TOKEN=$(zt_get_token)
    # Check if Zerotier Network is available, if not create new Network
    if [ "$(zt_get_networks $TMP_ZEROTIER_TOKEN | xargs)"="[]" ]; then
        echo "No networks available, creating new one"
        zt_create_network $TMP_ZEROTIER_TOKEN
        # zt_get_networks $TMP_ZEROTIER_TOKEN
    else
        echo "There is already a network created"
    fi
    # TODO join gateway and client to the network
    # Wait for Zerotier Gateway and Services to be ready
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
