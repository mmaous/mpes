# ==============================================================================
# MPES Platform Lifecycle Makefile
# Multi-region GKE Infrastructure, Network & GitOps Operations
# ==============================================================================

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Directory configuration
TF_DIR := infrastructure/tf
SCRIPTS_DIR := infrastructure/scripts
K8S_BOOTSTRAP_DIR := kubernetes/bootstrap

# Color output helpers
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

.PHONY: help up down status clean fmt tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy tf-output allow-ip vault-secrets credentials argocd-setup bootstrap-platform bootstrap-apps bootstrap-all argocd-teardown

# ------------------------------------------------------------------------------
# HELP (Default Target)
# ------------------------------------------------------------------------------

##@ Help

## Display this help screen with target descriptions
help:
	@echo -e "$(RED)mpes$(RESET)"
	@echo -e "$(RED)---------------$(RESET)"

	@echo -e "Usage: make $(GREEN)<target>$(RESET)\n"
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 1, index($$1, ":")-1); \
			helpSubtext = substr(lastLine, RSTART + 3, RLENGTH - 3); \
			printf "  $(GREEN)%-20s$(RESET) %s\n", helpCommand, helpSubtext; \
		} \
	} \
	/^##@/ { \
		printf "\n$(CYAN)%s$(RESET)\n", substr($$1, 5); \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

# ------------------------------------------------------------------------------
# END-TO-END LIFECYCLE WORKFLOWS
# ------------------------------------------------------------------------------

##@ End-to-End Workflows

## Spin up full platform: Terraform apply, IP authorization, cluster credentials, Argo CD setup & GitOps bootstrap
up: tf-apply credentials argocd-setup bootstrap-all
	@echo -e "$(GREEN)[SUCCESS] Full MPES platform up and bootstrapped!$(RESET)"

## Gracefully destroy full platform: Teardown Argo CD & GitOps workloads first, then destroy Terraform infrastructure
down: tf-destroy
	@echo -e "$(GREEN)[SUCCESS] Full MPES platform torn down cleanly.$(RESET)"

## Show operational status of GCP infrastructure, GKE clusters, and Argo CD workloads
status:
	@echo -e "$(CYAN)=== GKE Cluster Status ===$(RESET)"
	@gcloud container clusters list || true
	@echo -e "\n$(CYAN)=== Argo CD & GitOps Status (Primary Cluster) ===$(RESET)"
	@kubectl get applications,applicationsets -n argocd 2>/dev/null || echo -e "$(YELLOW)Unable to query Argo CD resources (cluster may be offline or unauthenticated).$(RESET)"

# ------------------------------------------------------------------------------
# INFRASTRUCTURE (TERRAFORM)
# ------------------------------------------------------------------------------

##@ Infrastructure (Terraform)

## Initialize Terraform working directory and download providers
tf-init:
	@echo -e "$(CYAN)Initializing Terraform...$(RESET)"
	@terraform -chdir=$(TF_DIR) init

## Format Terraform files recursively
tf-fmt:
	@echo -e "$(CYAN)Formatting Terraform files...$(RESET)"
	@terraform -chdir=$(TF_DIR) fmt -recursive

## Validate Terraform syntax and configuration integrity
tf-validate: tf-init
	@echo -e "$(CYAN)Validating Terraform configuration...$(RESET)"
	@terraform -chdir=$(TF_DIR) validate

## Generate and display a Terraform execution plan
tf-plan: tf-init
	@echo -e "$(CYAN)Planning Terraform infrastructure...$(RESET)"
	@terraform -chdir=$(TF_DIR) plan

## Apply Terraform changes to provision/update GCP infrastructure
tf-apply: tf-init
	@echo -e "$(CYAN)Applying Terraform infrastructure...$(RESET)"
	@terraform -chdir=$(TF_DIR) apply -auto-approve

## Destroy all Terraform-managed GCP infrastructure
tf-destroy: tf-init
	@echo -e "$(YELLOW)Destroying Terraform infrastructure...$(RESET)"
	@terraform -chdir=$(TF_DIR) destroy -auto-approve

## Show raw Terraform outputs
tf-output:
	@terraform -chdir=$(TF_DIR) output

# ------------------------------------------------------------------------------
# NETWORK & SECURITY
# ------------------------------------------------------------------------------

##@ Network & Security

## Dynamically add current workstation external IP to GKE master authorized networks
allow-ip:
	@echo -e "$(CYAN)Authorizing current IP on GKE control planes...$(RESET)"
	@bash $(SCRIPTS_DIR)/allow-my-ip.sh

## Upload Istio certificates and cluster remote secrets to GCP Secret Manager
vault-secrets:
	@echo -e "$(CYAN)Syncing certificates and secrets to GCP Secret Manager...$(RESET)"
	@bash $(SCRIPTS_DIR)/vault-secrets.sh

# ------------------------------------------------------------------------------
# KUBERNETES & GITOPS (ARGOCD)
# ------------------------------------------------------------------------------

##@ Kubernetes & GitOps (Argo CD)

## Fetch kubeconfig credentials for primary and secondary GKE clusters
credentials:
	@echo -e "$(CYAN)Fetching credentials for GKE clusters...$(RESET)"
	@PROJECT=$$(terraform -chdir=$(TF_DIR) output -raw project_id 2>/dev/null) || { echo -e "$(RED)Failed to fetch project_id from terraform outputs.$(RESET)"; exit 1; }; \
	PRIMARY_NAME=$$(terraform -chdir=$(TF_DIR) output -raw primary_cluster_name 2>/dev/null); \
	PRIMARY_LOC=$$(terraform -chdir=$(TF_DIR) output -raw primary_location 2>/dev/null); \
	SECONDARY_NAME=$$(terraform -chdir=$(TF_DIR) output -raw secondary_cluster_name 2>/dev/null); \
	SECONDARY_LOC=$$(terraform -chdir=$(TF_DIR) output -raw secondary_location 2>/dev/null); \
	gcloud container clusters get-credentials "$$PRIMARY_NAME" --location "$$PRIMARY_LOC" --project "$$PROJECT" && \
	gcloud container clusters get-credentials "$$SECONDARY_NAME" --location "$$SECONDARY_LOC" --project "$$PROJECT"

## Deploy Argo CD on primary cluster and register secondary cluster link
argocd-setup:
	@echo -e "$(CYAN)Setting up Argo CD...$(RESET)"
	@sh $(SCRIPTS_DIR)/setup-argocd.sh

## Apply root platform ApplicationSet to deploy cluster platform components (istio, cert-manager, external-secrets, etc.)
bootstrap-platform:
	@echo -e "$(CYAN)Applying platform root ApplicationSet...$(RESET)"
	@kubectl apply -f $(K8S_BOOTSTRAP_DIR)/root-platform.yaml

## Apply root applications ApplicationSet to deploy workloads
bootstrap-apps:
	@echo -e "$(CYAN)Applying apps root ApplicationSet...$(RESET)"
	@kubectl apply -f $(K8S_BOOTSTRAP_DIR)/root-apps.yaml

## Apply both platform and apps GitOps bootstrap manifests
bootstrap-all: bootstrap-platform bootstrap-apps

## Teardown Argo CD applications, cluster links, and Helm installation cleanly
argocd-teardown:
	@echo -e "$(YELLOW)Tearing down Argo CD and managed GitOps applications...$(RESET)"
	@sh $(SCRIPTS_DIR)/teardown-argocd.sh

# ------------------------------------------------------------------------------
# UTILITIES & REPOSITORY HYGIENE
# ------------------------------------------------------------------------------

##@ Utilities & Maintenance

## Format code and clean repository artifacts
fmt: tf-fmt clean

## Remove temporary files, OS artifacts (.DS_Store), and build leftovers
clean:
	@echo -e "$(CYAN)Cleaning repository artifacts...$(RESET)"
	@find . -name ".DS_Store" -type f -delete
	@find . -name "*.tmp" -type f -delete
	@echo -e "$(GREEN)Clean complete.$(RESET)"
