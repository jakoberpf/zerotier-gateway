#!/usr/bin/env bash

GIT_ROOT=$(git rev-parse --show-toplevel)
cd $GIT_ROOT

ZEROTIER_TEST_API="http://localhost/api"
ZEROTIER_TEST_API_HOST="zerotier.example.com"
ZEROTIER_TEST_NAMESPACE="zerotier"

zt_get_token() {
    uiPodName=$(kubectl get pods -n $ZEROTIER_TEST_NAMESPACE -o json | jq '.items[] | select(.metadata.labels.component=="ui") | .metadata.name' | xargs)
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
    if [[ "$(kind get clusters)" != *"zerotier-gateway"* ]]; then
        kind create cluster --config=$GIT_ROOT/test/kubernetes/kind.yaml
    fi
    # Install and setup Istio
    istioctl install -f $GIT_ROOT/test/kubernetes/istio.yaml -y
    # Wait for Istio to be ready
    while ! curl -I --silent --fail http://localhost:15021/healthz/ready; do
        echo >&2 'Istio down, retrying in 1s...'
        sleep 1
    done
    # Create testing namespaces
    kubectl create namespace $ZEROTIER_TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    # Deploy Zerotier controller
    kubectl create secret generic zerotier-admin-credentials --from-literal=username=admin --from-literal=password=admin -n $ZEROTIER_TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    helm upgrade --install zerotier-controller oci://ghcr.io/jakoberpf/charts/zerotier-controller --version 0.0.8 --values $GIT_ROOT/test/kubernetes/zerotier-controller-values.yaml -n $ZEROTIER_TEST_NAMESPACE
    # Wait for Zerotier controller to be ready
    while ! curl -I --silent --fail --header 'Host: zerotier.example.com' http://localhost/app/; do
        echo >&2 'Zerotier Controller down, retrying in 1s...'
        sleep 1
    done
    # Get Zerotier controller API token
    TMP_ZEROTIER_TOKEN=$(zt_get_token)
    # Check if Zerotier network is available, if not create new network
    if [ "$(zt_get_networks $TMP_ZEROTIER_TOKEN | xargs)"="[]" ]; then
        echo "No networks available, creating new one"
        zt_create_network $TMP_ZEROTIER_TOKEN
        # zt_get_networks $TMP_ZEROTIER_TOKEN
    else
        echo "There is already a network created"
    fi
    # Deploy Zerotier gateway chart
    kubectl apply -f $GIT_ROOT/test/kubernetes/zerotier-controller-pvc.yaml -n $ZEROTIER_TEST_NAMESPACE
    helm upgrade --install zerotier-gateway $GIT_ROOT/chart --values=$GIT_ROOT/test/kubernetes/zerotier-gateway-values.yaml -n $ZEROTIER_TEST_NAMESPACE
    # Wait for Zerotier gateway to be ready
    while ! curl -I --silent --fail --header 'Host: example.com' http://localhost; do
        echo >&2 'Zerotier Gateway down, retrying in 1s...'
        sleep 1
    done
    # Create index.html as configmaps
    kubectl create configmap zerotier-client-one-html --from-file=$GIT_ROOT/test/docker/default-one.html -n $ZEROTIER_TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl create configmap zerotier-client-two-html --from-file=$GIT_ROOT/test/docker/default-two.html -n $ZEROTIER_TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    # build Zerotier gateway client image and load into cluster
    docker build -t jakoberpf/zerotier-gateway-client:local $GIT_ROOT/test/docker
    kind load docker-image jakoberpf/zerotier-gateway-client:local --name zerotier-gateway
    #  and deploy test clients
    kubectl apply -f $GIT_ROOT/test/kubernetes/zerotier-gateway-clients.yaml -n $ZEROTIER_TEST_NAMESPACE
    # TODO join gateway and client to the network
    # Wait for Zerotier Gateway and Services to be ready
}

@test "should be able to curl gateway" {
    run bash -c "curl -s --header 'Host: example.com' http://localhost | grep title"
    assert_output --partial '<title>Welcome to the Example Gateway</title>'
}

# @test "should be able to curl service-one via the gateway" {
#     run bash -c "curl -s --header 'Host: one.example.com' http://localhost | grep title"
#     assert_output --partial '<title>Welcome to Service One</title>'
# }

# @test "should be able to curl service-two via the gateway" {
#     run bash -c "curl -s --header 'Host: two.example.com' http://localhost | grep title"
#     assert_output --partial '<title>Welcome to Service Two</title>'
# }

teardown_file() {
    kind delete cluster --name zerotier-gateway
}
