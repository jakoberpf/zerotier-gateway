#!/bin/bash

set -e

grepzt() {
  [ -f /var/lib/zerotier-one/zerotier-one.pid -a -n "$(cat /var/lib/zerotier-one/zerotier-one.pid 2>/dev/null)" -a -d "/proc/$(cat /var/lib/zerotier-one/zerotier-one.pid 2>/dev/null)" ]
  return $?
}

mkztfile() {
  file=$1
  mode=$2
  content=$3

  mkdir -p /var/lib/zerotier-one
  echo "$content" > "/var/lib/zerotier-one/$file"
  chmod "$mode" "/var/lib/zerotier-one/$file"
}

if [ "x$ZEROTIER_API_SECRET" != "x" ]; then
  mkztfile authtoken.secret 0600 "$ZEROTIER_API_SECRET"
fi

if [ "x$ZEROTIER_IDENTITY_PUBLIC" != "x" ]; then
  mkztfile identity.public 0644 "$ZEROTIER_IDENTITY_PUBLIC"
fi

if [ "x$ZEROTIER_IDENTITY_SECRET" != "x" ]; then
  mkztfile identity.secret 0600 "$ZEROTIER_IDENTITY_SECRET"
fi

mkztfile zerotier-one.port 0600 "9993"

killzerotier() {
  log "Killing zerotier"
  kill $(cat /var/lib/zerotier-one/zerotier-one.pid 2>/dev/null)
  exit 0
}

log_header() {
  echo -n "=>"
}

log_detail_header() {
  echo -n "===>"
}

log() {
  echo "$(log_header)" "$@"
}

log_params() {
  title=$1
  shift
  log "$title" "[$@]"
}

log_detail() {
  echo "$(log_detail_header)" "$@"
}

log_detail_params() {
  title=$1
  shift
  log_detail "$title" "[$@]"
}

trap killzerotier INT TERM

log "Configuring networks to join"
mkdir -p /var/lib/zerotier-one/networks.d

if [ "x$ZEROTIER_JOIN_NETWORKS" != "x" ]; then
  log_params "Joining networks from environment:" $ZEROTIER_JOIN_NETWORKS
  ids=(`echo $ZEROTIER_JOIN_NETWORKS | tr ',' ' '`)
  for i in "${ids[@]}"; do
    log_detail_params "Configuring join:" "$i"
    if [ "$i" = "8056c2e21c000001" ]; then
      log "WARNING! You are connecting to ZeroTier's Earth network!"
      log "If you join this or any other public network, make sure your computer is up to date on all security patches and you've stopped, locally firewalled, or password protected all services on your system that listen for outside connections."
    fi
    touch "/var/lib/zerotier-one/networks.d/${i}.conf"
  done
fi

log "Starting ZeroTier"
nohup /usr/sbin/zerotier-one &

while ! grepzt; do
  log_detail "ZeroTier hasn't started, waiting a second"

  if [ -f nohup.out ]
  then
    tail -n 10 nohup.out
  fi

  sleep 1
done

while [ $(zerotier-cli status -j | jq '.online') != "true" ]; do
  log_detail "ZeroTier still offline, waiting a second"

  sleep 1
done

log_params "Writing healthcheck for networks:" $ZEROTIER_JOIN_NETWORKS

cat >/healthcheck.sh <<EOF
#!/bin/bash
for i in $ZEROTIER_JOIN_NETWORKS
do
  [ "\$(zerotier-cli get \$i status)" = "OK" ] || exit 1
done
EOF

chmod +x /healthcheck.sh

log_params "Member info:" "$(zerotier-cli info)"

if [ "x$ZEROTIER_JOIN_NETWORKS" != "x" ]; then
  log_params "Checking IP(s) for networks from environment:" $ZEROTIER_JOIN_NETWORKS
  ids=(`echo $ZEROTIER_JOIN_NETWORKS | tr ',' ' '`)
  for i in "${ids[@]}"; do
      log_detail_params "Chec98king IP(s):" "$i"
      result=$(zerotier-cli listnetworks -j | jq -er '.[] | select(.id == "f82d90b853d7dc1a") | .assignedAddresses')
      echo $result
      while [ "$result" = "[]" ]; do
        log_detail "Network $i without address, waiting for IP(s)"
        sleep 1
        result=$(zerotier-cli listnetworks -j | jq -er '.[] | select(.id == "f82d90b853d7dc1a") | .assignedAddresses')
        echo $result
      done
      log_params "Network $i has adresses:" "$(zerotier-cli listnetworks -j | jq -r '.[] | select(.id == "$i") | .assignedAddresses | join(", ")')"
  done
fi
    
while true
do
  # log "Runnig Healthcheck"
  # /healthcheck.sh

  zerotier-cli listnetworks -j | jq -er '.[] | .assignedAddresses'

  sleep 1
done