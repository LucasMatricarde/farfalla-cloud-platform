#!/usr/bin/env bash
set -euo pipefail
# One-time GitOps bootstrap after ArgoCD is installed and manifests are
# placeholder-substituted. Requires KUBECONFIG set.
kubectl apply -f k8s/bootstrap/project.yaml
kubectl apply -f k8s/bootstrap/app-of-apps.yaml
echo "ArgoCD app-of-apps applied. Watch: kubectl -n argocd get applications -w"
