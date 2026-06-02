# Runbook — Deploy from zero

Prereqs: AWS account + creds, an existing EC2 key pair, Terraform, kubectl, kustomize, AWS CLI.

## 1. Remote state
```bash
cd terraform/state-backend
terraform init
terraform apply -var state_bucket_name=<globally-unique-bucket>
```

## 2. GitHub OIDC provider (once per account, if absent)
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

## 3. Provision infra
```bash
cd terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars   # edit operator_cidr, key_name, github_repo
terraform init -backend-config="bucket=<bucket>" -backend-config="dynamodb_table=farfalla-tf-locks"
terraform apply
```
Note outputs: `node_public_ip`, `sslip_domain`, `ecr_repository_urls`, `rds_endpoint`, `cd_role_arn`, `terraform output -raw rds_password`.

## 4. Substitute placeholders in manifests
Replace before bootstrap (EIP-derived host = dashes, e.g. `1-2-3-4.sslip.io`):
- `__GITHUB_REPO_URL__` (k8s/bootstrap/app-of-apps.yaml)
- `__ACME_EMAIL__` (cert-manager/cluster-issuer.yaml)
- `__GRAFANA_HOST__`, `__GRAFANA_ADMIN_PASSWORD__` (kube-prometheus-stack)
- `__APP_HOST__` (apps/farfalla certificate.yaml, ingressroute.yaml)
- `__RDS_ENDPOINT__` (backend-config.yaml)
- `__ECR_BACKEND_REPO__`, `__ECR_FRONTEND_REPO__` and `__BACKEND_IMAGE__`/`__FRONTEND_IMAGE__` (kustomization.yaml)
Commit and push these to `main`.

## 5. GitHub repo variables
Set: `APP_REPO`, `APP_REF`, `CD_ROLE_ARN`.

## 6. Cluster bootstrap
```bash
./scripts/fetch-kubeconfig.sh <node_public_ip> <key.pem>
export KUBECONFIG=$PWD/kubeconfig
./scripts/install-argocd.sh
# create the DB secret out-of-band (gitignored):
kubectl -n farfalla create secret generic backend-secret \
  --from-literal=SPRING_DATASOURCE_USERNAME=erp \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$(cd terraform/envs/prod && terraform output -raw rds_password)"
./scripts/bootstrap-cluster.sh
```

## 7. Verify
- `kubectl -n argocd get applications` -> all Synced/Healthy
- `https://app.<EIP>.sslip.io` loads with valid TLS, login works
- `https://grafana.<EIP>.sslip.io` shows JVM/HTTP dashboards
- Push to app repo main -> CD bumps tag -> ArgoCD redeploys

## Teardown
`kubectl delete -f k8s/bootstrap/app-of-apps.yaml` then `terraform destroy` (prod, then state-backend).
