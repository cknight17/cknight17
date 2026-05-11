# cknight17 terraform — setup / apply / destroy
#
# First-time setup (per AWS account):
#   make bootstrap   # state bucket, lock table, IAM (run once, by an admin)
#   make secrets     # seed GitHub OAuth client id/secret into SSM
#   make init        # init dev with the right backend bucket
#
# Day-to-day:
#   make plan
#   make apply
#
# Teardown (clean):
#   make destroy     # runs ALB cleanup first, then terraform destroy
#
# Notes:
#   - AWS_PROFILE / AWS_REGION env vars are respected.
#   - REGION overrides the default us-east-1 (e.g. `make apply REGION=us-west-2`).

SHELL := /usr/bin/env bash

PROJECT       := cknight17
ENV           := dev
REGION        ?= us-east-1
DEV_DIR       := environments/$(ENV)
BOOTSTRAP_DIR := bootstrap
CLUSTER       := $(PROJECT)-$(ENV)

ACCOUNT_ID = $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)

.PHONY: help check-aws bootstrap secrets init plan apply clean-alb destroy console fmt validate

help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check-aws: ## Verify AWS credentials are set
	@if [ -z "$(ACCOUNT_ID)" ]; then \
		echo "ERROR: no AWS credentials. Run 'aws sso login' or set AWS_PROFILE." >&2; \
		exit 1; \
	fi
	@echo "AWS account: $(ACCOUNT_ID)  region: $(REGION)"

bootstrap: check-aws ## Create state bucket, lock table, IAM (run once per account)
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply

secrets: check-aws ## Seed GitHub OAuth client id/secret into SSM
	@read -p "GitHub OAuth Client ID: " ID; \
	read -rsp "GitHub OAuth Client Secret: " SECRET; echo; \
	aws ssm put-parameter \
		--name "/$(PROJECT)/$(ENV)/github-oauth/client-id" \
		--value "$$ID" --type SecureString --overwrite --region $(REGION) >/dev/null; \
	aws ssm put-parameter \
		--name "/$(PROJECT)/$(ENV)/github-oauth/client-secret" \
		--value "$$SECRET" --type SecureString --overwrite --region $(REGION) >/dev/null; \
	echo "  stored /$(PROJECT)/$(ENV)/github-oauth/{client-id,client-secret}"

init: check-aws ## terraform init with derived backend config
	cd $(DEV_DIR) && terraform init -reconfigure \
		-backend-config="bucket=$(PROJECT)-terraform-state-$(ACCOUNT_ID)"

plan: check-aws ## terraform plan
	cd $(DEV_DIR) && terraform plan

apply: check-aws ## terraform apply
	cd $(DEV_DIR) && terraform apply

clean-alb: check-aws ## Delete Ingresses/LB Services and wait for ALB controller to clean up AWS resources
	$(DEV_DIR)/cleanup-alb.sh $(CLUSTER) $(REGION)

destroy: clean-alb ## Pre-clean ALB resources, then terraform destroy
	cd $(DEV_DIR) && terraform destroy -refresh=false

console: check-aws ## Open AWS console sign-in for this account
	@open "https://$(ACCOUNT_ID).signin.aws.amazon.com/console"

fmt: ## terraform fmt across the tree
	terraform fmt -recursive

validate: check-aws ## terraform validate in dev
	cd $(DEV_DIR) && terraform validate
