#!/usr/bin/env bash
set -euo pipefail
# Installs ArgoCD into the cluster. Requires KUBECONFIG pointing at the k3s node.
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.2}"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
