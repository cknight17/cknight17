# cknight17 — AWS EKS Infrastructure

Production-style Kubernetes platform on AWS, managed with Terraform and ArgoCD.
Infrastructure changes deploy via **Digger** (Terraform CI/CD in GitHub Actions) using **OIDC** — no static AWS credentials.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AWS Account                       │
│  ┌───────────────────────────────────────────────┐  │
│  │                 VPC (10.0.0.0/16)             │  │
│  │  ┌─────────────┐       ┌─────────────┐       │  │
│  │  │ Private Sub  │       │ Private Sub  │      │  │
│  │  │   AZ-1       │       │   AZ-2       │      │  │
│  │  │  ┌────────┐  │       │  ┌────────┐  │      │  │
│  │  │  │EKS Node│  │       │  │EKS Node│  │      │  │
│  │  │  └────────┘  │       │  └────────┘  │      │  │
│  │  └─────────────┘       └─────────────┘       │  │
│  │  ┌─────────────┐       ┌─────────────┐       │  │
│  │  │ Public Sub   │       │ Public Sub   │      │  │
│  │  │   AZ-1       │       │   AZ-2       │      │  │
│  │  └─────────────┘       └─────────────┘       │  │
│  └───────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  Aurora   │  │ DynamoDB │  │    S3    │          │
│  │ (Phase 3) │  │(Phase 3) │  │(Phase 3) │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────────────────────────────────────┘
```

## CI/CD Flow

```
Developer ──► PR to main ──► GitHub Actions
                                  │
                         ┌────────┴────────┐
                         │  Digger + OIDC   │
                         │                  │
                         │  1. tf fmt check │
                         │  2. tf plan      │
                         │  3. Comment plan │
                         │     on PR        │
                         └────────┬────────┘
                                  │
                    PR comment: "digger apply"
                                  │
                         ┌────────┴────────┐
                         │  tf apply        │
                         │  (in GH Actions) │
                         └─────────────────┘
```

**No static AWS credentials.** GitHub Actions authenticates via OIDC → assumes an IAM role → gets temporary credentials. Digger provides PR-level locking, plan comments, and safe apply-before-merge.

## Repository Structure

```
.
├── digger.yml              # Digger project config
├── .github/workflows/
│   ├── digger.yml          # Digger plan/apply workflow
│   └── lint.yml            # Format & validate checks
├── terraform/
│   ├── bootstrap/          # S3 backend, DynamoDB locks, OIDC provider, GH Actions role
│   ├── environments/dev/   # Dev environment root module
│   └── modules/
│       ├── vpc/            # VPC, subnets, NAT, IGW
│       ├── eks/            # EKS cluster + managed node groups
│       ├── argocd/         # ArgoCD Helm installation
│       ├── aurora/         # Aurora PostgreSQL (Phase 3)
│       ├── dynamodb/       # DynamoDB tables (Phase 3)
│       └── s3/             # S3 buckets (Phase 3)
├── k8s/
│   ├── argocd/             # ArgoCD app-of-apps config
│   └── apps/               # Application manifests
└── .github/workflows/      # CI/CD pipelines
```

## Quick Start

### Prerequisites
- AWS CLI configured with credentials for your AWS account
- Terraform >= 1.5
- kubectl

### 1. Bootstrap (one-time, from local machine)

This creates the S3 state bucket, lock tables, GitHub OIDC provider, and the IAM role for CI/CD.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Save the `github_actions_role_arn` and `state_bucket` outputs — you'll need them next.

### 2. Initialize dev environment locally

```bash
cd terraform/environments/dev
# Create backend config with your account's state bucket
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "bucket = \"cknight17-terraform-state-${ACCOUNT_ID}\"" > backend.hcl
terraform init -backend-config=backend.hcl
```

### 3. Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** in your GitHub repo:

| Secret Name    | Value                                                        |
|----------------|--------------------------------------------------------------|
| `AWS_ROLE_ARN` | The `github_actions_role_arn` output from the bootstrap step  |

### 4. Deploy via PR

```bash
git checkout -b initial-infra
git push -u origin initial-infra
# Open PR to main → Digger runs terraform plan automatically
# Review the plan comment on the PR
# Comment "digger apply" → infrastructure deploys
# Merge the PR
```

### 5. Connect to Cluster

```bash
aws eks update-kubeconfig --name cknight17-dev --region us-east-1
kubectl get nodes
```

### 6. Access ArgoCD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080, user: admin
```

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | VPC + EKS + IAM/OIDC | ✅ Ready |
| 2 | ArgoCD GitOps | ✅ Ready |
| 2.5 | Digger CI/CD + OIDC auth | ✅ Ready |
| 3 | Aurora / DynamoDB / S3 | 📋 Scaffolded |
| 4 | Demo workloads | 📋 Scaffolded |

## Cost Estimate (Dev)
- EKS control plane: ~$73/mo
- 2× t3.medium nodes: ~$60/mo
- NAT Gateway: ~$32/mo
- **Total: ~$165/mo** (can scale down to 1 node / ~$135/mo)
