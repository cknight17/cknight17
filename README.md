# cknight17 — AWS EKS Infrastructure

Production-style Kubernetes platform on AWS, managed with Terraform and ArgoCD.
Infrastructure changes deploy via **Digger** (Terraform CI/CD in GitHub Actions) using **OIDC** — no static AWS credentials.

## Architecture

### Infrastructure

```mermaid
graph TB
    subgraph Internet
        User([User / Browser])
        GoDaddy[GoDaddy<br/>knighttechnology.net<br/>NS → Route 53]
    end

    subgraph AWS["AWS Account (659474314285)"]
        R53[Route 53<br/>knighttechnology.net]
        ACM[ACM<br/>*.knighttechnology.net]

        subgraph VPC["VPC (10.0.0.0/16)"]
            subgraph Public["Public Subnets"]
                ALB[Application Load Balancer<br/>HTTPS :443]
                NAT[NAT Gateway]
                IGW[Internet Gateway]
            end

            subgraph Private["Private Subnets (AZ-1 + AZ-2)"]
                subgraph EKS["EKS Cluster (K8s 1.32)"]
                    ALBC[AWS LB Controller<br/>IRSA]
                    ArgoCD[ArgoCD<br/>argocd.knighttechnology.net]
                    Demo[Demo App<br/>demo.knighttechnology.net]
                end
                Node1[EKS Node<br/>t3.medium]
                Node2[EKS Node<br/>t3.medium]
            end
        end

        subgraph State["Terraform State"]
            S3[(S3 Bucket<br/>terraform.tfstate)]
            DDB[(DynamoDB<br/>State Locks)]
        end

        subgraph IAM["IAM"]
            AdminUser[IAM User: cknight<br/>AdministratorAccess]
            GHRole[IAM Role: github-actions<br/>OIDC Federation]
        end
    end

    User -->|HTTPS| R53
    R53 -->|Alias| ALB
    ALB -->|TLS via| ACM
    ALB -->|/argocd.*/ | ArgoCD
    ALB -->|/demo.*/ | Demo
    EKS --- Node1
    EKS --- Node2
    Private -->|Outbound via| NAT
    NAT --> IGW
    ALBC -.->|Manages| ALB
    ArgoCD -.->|GitOps sync| GitHub

    style AWS fill:#f5f5f5,stroke:#232f3e
    style VPC fill:#e8f4fd,stroke:#1a73e8
    style EKS fill:#e8f5e9,stroke:#2e7d32
    style Public fill:#fff3e0,stroke:#e65100
    style Private fill:#e3f2fd,stroke:#1565c0
    style State fill:#fce4ec,stroke:#c62828
    style IAM fill:#f3e5f5,stroke:#6a1b9a
```

### CI/CD Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GA as GitHub Actions
    participant OIDC as AWS OIDC
    participant TF as Terraform
    participant AWS as AWS Resources

    Dev->>GH: Open PR to main
    GH->>GA: Trigger workflow (pull_request)
    GA->>OIDC: Assume role via OIDC<br/>(no static credentials)
    OIDC-->>GA: Temporary credentials

    rect rgb(232, 245, 233)
        Note over GA,TF: Automatic on PR
        GA->>TF: terraform fmt -check
        GA->>TF: terraform plan
        TF-->>GA: Plan output
        GA->>GH: Comment plan on PR
    end

    Dev->>GH: Comment "digger apply"
    GH->>GA: Trigger workflow (issue_comment)
    GA->>OIDC: Assume role via OIDC

    rect rgb(255, 243, 224)
        Note over GA,AWS: Manual trigger
        GA->>TF: terraform apply
        TF->>AWS: Create/update resources
        GA->>GH: Comment with apply run link
    end

    Dev->>GH: Merge PR
```

### GitOps Application Delivery

```mermaid
graph LR
    subgraph GitHub
        Repo[cknight17/cknight17<br/>k8s/ manifests]
    end

    subgraph EKS["EKS Cluster"]
        ArgoCD[ArgoCD]
        RootApp[Root App<br/>app-of-apps]
        DemoApp[demo-app<br/>namespace]
    end

    Repo -->|watches main branch| ArgoCD
    ArgoCD -->|syncs| RootApp
    RootApp -->|manages| DemoApp

    style GitHub fill:#f5f5f5,stroke:#333
    style EKS fill:#e8f5e9,stroke:#2e7d32
```

**No static AWS credentials.** GitHub Actions authenticates via OIDC, assumes an IAM role, and gets temporary credentials. Digger orchestrates plan/apply with PR comments.

## Repository Structure

```
.
├── digger.yml              # Digger project config
├── .githooks/pre-commit    # Terraform fmt pre-commit hook
├── .github/workflows/
│   ├── digger.yml          # Digger plan/apply workflow
│   └── lint.yml            # Format & validate checks
├── terraform/
│   ├── bootstrap/          # S3 backend, DynamoDB locks, OIDC provider, IAM user, GH Actions role
│   ├── environments/dev/   # Dev environment root module
│   └── modules/
│       ├── vpc/            # VPC, subnets, NAT, IGW
│       ├── eks/            # EKS cluster + managed node groups + access entries
│       ├── argocd/         # ArgoCD Helm installation
│       ├── alb-controller/ # AWS Load Balancer Controller (Helm + IRSA)
│       ├── dns/            # Route 53, ACM wildcard cert, Ingress resources
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

Get the admin password, then open https://argocd.knighttechnology.net:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Open https://argocd.knighttechnology.net, user: admin
```

## Live URLs

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.knighttechnology.net |
| Demo App | https://demo.knighttechnology.net |

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | VPC + EKS + IAM/OIDC | ✅ Running |
| 2 | ArgoCD GitOps | ✅ Running |
| 2.5 | Digger CI/CD + OIDC auth | ✅ Running |
| 3 | DNS + HTTPS + ALB Ingress | ✅ Running |
| 4 | Aurora / DynamoDB / S3 | 📋 Scaffolded |
| 5 | Demo workloads | 📋 Scaffolded |

## Cost Estimate (Dev)
- EKS control plane: ~$73/mo
- 2x t3.medium nodes: ~$60/mo
- NAT Gateway: ~$32/mo
- ALB: ~$16/mo
- Route 53 hosted zone: ~$0.50/mo
- **Total: ~$181/mo** (can scale down to 1 node / ~$151/mo)

GPU spend is on top of this and only accrues while a GPU node is running — see below.

## GPU Workloads

The cluster runs CPU workloads on a fixed managed node group and provisions
GPU nodes on demand via **Karpenter**. Idle cost: ~$0 (no GPU nodes running).
Total spend is bounded by an AWS Budget alarm (default $100/mo, edit
`monthly_budget_usd` to change).

### Approximate GPU hourly cost (us-east-1)

| Instance     | vCPU | GPU      | VRAM  | Spot     | On-Demand |
|--------------|------|----------|-------|----------|-----------|
| g6.xlarge    | 4    | 1× L4    | 24 GB | ~$0.25/h | ~$0.81/h  |
| g6.2xlarge   | 8    | 1× L4    | 24 GB | ~$0.30/h | ~$0.97/h  |
| g5.xlarge    | 4    | 1× A10G  | 24 GB | ~$0.30/h | ~$1.00/h  |
| g5.2xlarge   | 8    | 1× A10G  | 24 GB | ~$0.35/h | ~$1.21/h  |

Spot prices fluctuate; these are typical numbers. Karpenter prefers spot and
falls through to on-demand only if spot capacity isn't available in the AZ.

### Scheduling onto a GPU node

GPU nodes are tainted `nvidia.com/gpu=true:NoSchedule` so regular workloads
don't land on them. A training pod needs the matching toleration, the
`workload: gpu-ml` node selector, and a `nvidia.com/gpu` resource request:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: trainer
  namespace: cameron
spec:
  template:
    spec:
      restartPolicy: Never
      tolerations:
        - key: nvidia.com/gpu
          operator: Equal
          value: "true"
          effect: NoSchedule
      nodeSelector:
        workload: gpu-ml
      containers:
        - name: trainer
          image: <your image>
          resources:
            limits:
              nvidia.com/gpu: 1
```

When the pod is unschedulable, Karpenter provisions a `g6.xlarge` or
`g5.xlarge` (xlarge or 2xlarge) within ~45 seconds. When the pod finishes
and the node sits empty for 30 seconds, Karpenter terminates it.

### Guardrails

- **NodePool CPU limit:** 32 vCPU total → at most ~4 single-GPU nodes
  concurrently.
- **AWS Budget:** alerts at 50% forecasted / 80% actual / 100% actual against
  the monthly cap.
- **`cameron` namespace ResourceQuota:** 2 GPUs, 16 vCPU, 64 Gi memory.
