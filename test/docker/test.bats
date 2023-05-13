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
    docker compose build
    docker compose --file docker-compose.yaml up -d

    # Wait for Zerotier Controller to be ready
    while ! curl --silent --fail http://localhost:4000; do
        echo >&2 'Site down, retrying in 1s...'
        sleep 1
    done

    TMP_ZEROTIER_TOKEN=$(zt_get_token)

    if [ "$(zt_get_networks $TMP_ZEROTIER_TOKEN | xargs)"="[]" ]; then
        echo "No networks created, creating new one"
        zt_create_network $TMP_ZEROTIER_TOKEN
        # zt_get_networks $TMP_ZEROTIER_TOKEN
    else
        echo "There is already a network created"
    fi

    # TODO join gateway and client to the network

    # Wait for Zerotier Gateway to be ready
    while ! curl --silent --fail http://localhost:8080; do
        echo >&2 'Site down, retrying in 1s...'
        sleep 1
    done

    while ! curl --silent --fail http://localhost:8081; do
        echo >&2 'Site down, retrying in 1s...'
        sleep 1
    done

    while ! curl --silent --fail http://localhost:8082; do
        echo >&2 'Site down, retrying in 1s...'
        sleep 1
    done
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
#     docker compose --file docker-compose.yaml down
# }
