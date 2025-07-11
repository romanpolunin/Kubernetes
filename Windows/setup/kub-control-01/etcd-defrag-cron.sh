#!/bin/bash
# etcd-defrag-cron.sh
# Schedules a weekly cron job to defragment etcd on a Kubernetes control plane node
# Usage: sudo ./etcd-defrag-cron.sh

set -e

# etcdctl parameters (adjust if your certs are in a different location)
ENDPOINT="https://127.0.0.1:2379"
CERT="/etc/kubernetes/pki/etcd/server.crt"
KEY="/etc/kubernetes/pki/etcd/server.key"
CACERT="/etc/kubernetes/pki/etcd/ca.crt"

# Create the defrag script
cat <<EOF | sudo tee /usr/local/bin/etcd-defrag.sh > /dev/null
#!/bin/bash
set -e

# Get the etcd pod name
ETCD_POD=\$(sudo crictl pods --name=etcd -q | head -n 1)
ETCD_CONTAINER=\$(sudo crictl ps --pod=\$ETCD_POD --name=etcd -q | head -n 1)

if [ -z "\$ETCD_CONTAINER" ]; then
  echo "Error: etcd container not found" >&2
  exit 1
fi

# Run defrag from inside the container
sudo crictl exec \$ETCD_CONTAINER sh -c "ETCDCTL_API=3 etcdctl --endpoints=$ENDPOINT --cert=$CERT --key=$KEY --cacert=$CACERT defrag"
EOF
sudo chmod +x /usr/local/bin/etcd-defrag.sh

# Add a weekly cron job (Sunday at 2:30am)
CRON_JOB="30 2 * * 0 root /usr/local/bin/etcd-defrag.sh >> /var/log/etcd-defrag.log 2>&1"
CRON_FILE="/etc/cron.d/etcd-defrag"
echo "$CRON_JOB" | sudo tee $CRON_FILE > /dev/null

sudo chmod 644 $CRON_FILE

echo "etcd defragmentation cron job installed. It will run weekly on Sunday at 2:30am."
echo "You can check logs in /var/log/etcd-defrag.log."
