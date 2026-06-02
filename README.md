# Farfalla Cloud Platform

GitOps deployment of the ERP-Farfalla app on AWS (k3s + ArgoCD), provisioned with Terraform, delivered by GitHub Actions, observed with Prometheus/Grafana/Loki.

## Pillars
- **IaC:** Terraform — VPC, EC2/k3s, RDS, ECR, S3/DynamoDB state, GitHub OIDC.
- **K8s:** k3s on a single EC2, Traefik ingress, cert-manager TLS.
- **CI/CD:** GitHub Actions — infra validation on PR; build→ECR + GitOps tag bump on merge.
- **GitOps:** ArgoCD app-of-apps.
- **Observability:** kube-prometheus-stack + Loki.

## Deploy quickstart
Full deploy order in `docs/runbook.md`. Architecture in `docs/architecture.md`.

> v1 scope: single node, single env. Future: EKS, multi-env, autoscaling, Datadog, canary.
