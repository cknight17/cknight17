#!/usr/bin/env bash
# Pre-destroy cleanup for ALB controller-managed resources.
#
# The aws-load-balancer-controller creates ALBs, target groups, and
# security groups in AWS in response to Kubernetes Ingress/Service
# objects. Those resources live outside Terraform state.
#
# Without this script, `terraform destroy` removes the controller's
# helm release before it finishes cleaning up, leaving orphan
# k8s-* security groups attached to the VPC. The VPC then refuses
# to delete and you end up in the AWS console untangling SGs by hand.
#
# This script:
#   1. Deletes all Ingresses (the controller will tear down its ALBs/SGs)
#   2. Deletes all LoadBalancer-type Services (same story for NLBs)
#   3. Waits for AWS to actually finish removing those resources
#
# Safe to re-run. Tolerates a missing/already-gone cluster.

set -uo pipefail

CLUSTER_NAME="${1:-}"
REGION="${2:-us-east-1}"

if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: $0 <cluster-name> [region]" >&2
  exit 1
fi

echo "==> Pre-destroy ALB cleanup: cluster=$CLUSTER_NAME region=$REGION"

if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1 || true

  echo "    deleting all Ingresses..."
  kubectl delete ingress --all --all-namespaces --wait=true --timeout=180s 2>/dev/null || true

  echo "    deleting all LoadBalancer Services..."
  kubectl get svc --all-namespaces -o json 2>/dev/null \
    | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null \
    | while read -r ns name; do
        [ -n "${name:-}" ] && kubectl -n "$ns" delete svc "$name" --wait=true --timeout=120s 2>/dev/null || true
      done
else
  echo "    cluster not reachable, skipping kubectl steps (assuming already destroyed)"
fi

echo "==> Waiting for ALBs/NLBs tagged elbv2.k8s.aws/cluster=$CLUSTER_NAME to disappear..."
for i in $(seq 1 60); do
  ARNS=$(aws resourcegroupstaggingapi get-resources \
    --region "$REGION" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER_NAME" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null)
  if [ -z "$ARNS" ] || [ "$ARNS" = "None" ]; then
    echo "    done"
    break
  fi
  echo "    still present: $ARNS"
  sleep 10
done

echo "==> Waiting for k8s-managed security groups (tag elbv2.k8s.aws/cluster=$CLUSTER_NAME) to disappear..."
for i in $(seq 1 30); do
  SG_IDS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=tag:elbv2.k8s.aws/cluster,Values=$CLUSTER_NAME" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)
  if [ -z "$SG_IDS" ] || [ "$SG_IDS" = "None" ]; then
    echo "    done"
    break
  fi
  echo "    still present: $SG_IDS"
  sleep 10
done

echo "==> ALB cleanup complete"
