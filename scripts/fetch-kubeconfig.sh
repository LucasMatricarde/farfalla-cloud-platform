#!/usr/bin/env bash
set -euo pipefail
# Usage: ./fetch-kubeconfig.sh <EC2_PUBLIC_IP> <SSH_KEY_PATH>
# Pulls the EIP-rewritten kubeconfig the node wrote in user_data.
IP="${1:?EC2 public IP required}"
KEY="${2:?SSH key path required}"

scp -o StrictHostKeyChecking=accept-new -i "$KEY" \
  "ubuntu@${IP}:/home/ubuntu/kubeconfig.yaml" ./kubeconfig
echo "Wrote ./kubeconfig — use: export KUBECONFIG=\$PWD/kubeconfig"
