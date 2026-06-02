# Architecture

```
Dev push -> GitHub Actions (CI validate / CD build->ECR + tag bump)
                                    |
                       git commit to k8s/ --> ArgoCD (in-cluster) auto-sync
AWS:
  VPC
    public subnet: EC2 t3.small (Elastic IP) -> k3s
       Traefik ingress (built-in) / cert-manager / ArgoCD
       backend + frontend pods / Prometheus, Grafana, Loki
    private subnets (2 AZ): RDS Postgres 17 (db.t3.micro)  SG: 5432 from EC2 SG
  ECR (backend, frontend)  |  S3 + DynamoDB (TF state + lock)
Recruiter -> https://app.<EIP>.sslip.io   https://grafana.<EIP>.sslip.io
```

## Components
- **Terraform** (`terraform/`): state-backend (S3+DynamoDB), modules network/ecr/rds/ec2-k3s, prod env + GitHub OIDC role.
- **k3s**: single node, built-in Traefik ingress, cert-manager Let's Encrypt TLS.
- **ArgoCD**: app-of-apps syncs platform (cert-manager, kube-prometheus-stack, loki) and the Farfalla app.
- **GitHub Actions**: CI validates infra + builds/tests app; CD pushes images to ECR (OIDC) and bumps the GitOps tag.
- **Observability**: Prometheus scrapes `/actuator/prometheus` via ServiceMonitor; Grafana dashboards; Loki/Promtail logs.

## Request flow
Recruiter -> app.<EIP>.sslip.io -> Traefik (TLS) -> frontend pod (nginx/Angular); `/api`,`/actuator`,`/swagger-ui` -> backend pod -> RDS over private subnet.

## Security
GitHub OIDC (no static keys), EC2 instance role (ECR pull), RDS private + SG-locked, SSH locked to operator IP.
