#!/bin/bash
set -ex

# Fail if KUB_CONTROL_PLANE_LB is not a valid IP address
if ! echo "$KUB_CONTROL_PLANE_LB" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  echo "Error: KUB_CONTROL_PLANE_LB is not set to a valid IP address: '$KUB_CONTROL_PLANE_LB'" >&2
  exit 1
fi

# Fail if KUB_CONTROL_PLANE_01 is not a valid IP address
if ! echo "$KUB_CONTROL_PLANE_01" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  echo "Error: KUB_CONTROL_PLANE_01 is not set to a valid IP address: '$KUB_CONTROL_PLANE_01'" >&2
  exit 1
fi

# Fail if KUB_CONTROL_PLANE_02 is not a valid IP address
if ! echo "$KUB_CONTROL_PLANE_02" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  echo "Error: KUBE_CONTROL_PLANE_02 is not set to a valid IP address: '$KUBECONTROL_PLANE_02'" >&2
  exit 1
fi

# 1. install HAProxy and common stuff
CACHE_DIR="/home/ubuntu/ext-common"

# Install common stuff
sudo apt-get update -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages
sudo apt-get install -y -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages \
    apt-transport-https=* ca-certificates=* curl=* haproxy=*

# 3. Create HAProxy config file 
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg

global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    
    # pidfile /home/ubuntu/data/haproxy.pid
    # server-state-file /home/ubuntu/data/server-state
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
    ssl-default-bind-options no-sslv3

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend kubernetes-api
    bind ${KUB_CONTROL_PLANE_LB}:6443
    mode tcp
    default_backend kubernetes-masters

backend kubernetes-masters
    mode tcp
    balance roundrobin
    option httpchk GET /healthz
    http-check send hdr Host ${KUB_CONTROL_PLANE_LB}
    option tcp-check
    
    server cp1 ${KUB_CONTROL_PLANE_01}:6443 check check-ssl verify none inter 5s fall 2 rise 1
    server cp2 ${KUB_CONTROL_PLANE_02}:6443 check check-ssl verify none inter 5s fall 2 rise 1

listen stats
    # my server has 2 IP addresses, but you can use *:<port> to listen on all interfaces and on the specific port
    bind *:80
    mode http
    stats enable
    stats uri /
    # stats hide-version
    # stats realm Haproxy\ Statistics
    # stats auth username:password
EOF

sudo systemctl restart haproxy
sudo systemctl enable haproxy