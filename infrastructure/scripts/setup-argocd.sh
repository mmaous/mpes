#!/bin/sh
set -eu

# Colorized logging using POSIX printf
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf "%b[INFO]%b %s\n" "$BLUE" "$NC" "$1"; }
log_success() { printf "%b[SUCCESS]%b %s\n" "$GREEN" "$NC" "$1"; }
log_warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"; }
log_error() { printf "%b[ERROR]%b %s\n" "$RED" "$NC" "$1"; }

# 1. Pre-flight CLI tool validation
log_info "Validating required CLI tools..."
for tool in gcloud kubectl helm argocd; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_error "Required tool '$tool' is not installed or not in PATH."
    exit 1
  fi
done

# Resolve directory paths (POSIX compatible $0 path expansion)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${TF_DIR:-$SCRIPT_DIR/../tf}"
REPO_ROOT="$SCRIPT_DIR/../.."

# 2. Fetch parameters from Environment Variables or fallback to Terraform output
PROJECT="${GCP_PROJECT_ID:-}"
PRIMARY_NAME="${PRIMARY_CLUSTER_NAME:-}"
PRIMARY_LOC="${PRIMARY_LOCATION:-}"
SECONDARY_NAME="${SECONDARY_CLUSTER_NAME:-}"
SECONDARY_LOC="${SECONDARY_LOCATION:-}"

if [ -z "$PROJECT" ] || [ -z "$PRIMARY_NAME" ] || [ -z "$PRIMARY_LOC" ] || [ -z "$SECONDARY_NAME" ] || [ -z "$SECONDARY_LOC" ]; then
  if [ -d "$TF_DIR" ] && command -v terraform >/dev/null 2>&1; then
    log_info "Reading cluster details from Terraform outputs in $TF_DIR ..."
    ORIG_DIR="$(pwd)"
    cd "$TF_DIR"
    PROJECT="${PROJECT:-$(terraform output -raw project_id 2>/dev/null || true)}"
    PRIMARY_NAME="${PRIMARY_NAME:-$(terraform output -raw primary_cluster_name 2>/dev/null || true)}"
    PRIMARY_LOC="${PRIMARY_LOC:-$(terraform output -raw primary_location 2>/dev/null || true)}"
    SECONDARY_NAME="${SECONDARY_NAME:-$(terraform output -raw secondary_cluster_name 2>/dev/null || true)}"
    SECONDARY_LOC="${SECONDARY_LOC:-$(terraform output -raw secondary_location 2>/dev/null || true)}"
    cd "$ORIG_DIR"
  fi
fi

if [ -z "$PROJECT" ] || [ -z "$PRIMARY_NAME" ] || [ -z "$PRIMARY_LOC" ] || [ -z "$SECONDARY_NAME" ] || [ -z "$SECONDARY_LOC" ]; then
  log_error "Unable to resolve cluster configuration."
  log_error "Please set GCP_PROJECT_ID, PRIMARY_CLUSTER_NAME, PRIMARY_LOCATION, SECONDARY_CLUSTER_NAME, and SECONDARY_LOCATION or run terraform apply."
  exit 1
fi

CTX_PRIMARY="gke_${PROJECT}_${PRIMARY_LOC}_${PRIMARY_NAME}"
CTX_SECONDARY="gke_${PROJECT}_${SECONDARY_LOC}_${SECONDARY_NAME}"

# 3. Authenticate cluster credentials
log_info "Fetching credentials for primary cluster ($PRIMARY_NAME in $PRIMARY_LOC)..."
gcloud container clusters get-credentials "$PRIMARY_NAME" --location "$PRIMARY_LOC" --project "$PROJECT"

log_info "Fetching credentials for secondary cluster ($SECONDARY_NAME in $SECONDARY_LOC)..."
gcloud container clusters get-credentials "$SECONDARY_NAME" --location "$SECONDARY_LOC" --project "$PROJECT"

# 4. Deploy Argo CD via Helm with pinned chart version
ARGO_CD_CHART_VERSION="${ARGO_CD_CHART_VERSION:-7.7.12}"
log_info "Deploying Argo CD (Helm Chart v${ARGO_CD_CHART_VERSION}) on primary cluster..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null 2>&1

helm upgrade --install argocd argo/argo-cd \
    --version "$ARGO_CD_CHART_VERSION" \
    --namespace argocd \
    --create-namespace \
    --kube-context "$CTX_PRIMARY" \
    -f "$REPO_ROOT/kubernetes/platform/argocd/values.yaml"

log_info "Waiting for Argo CD repo-server to reach Ready state..."
kubectl --context "$CTX_PRIMARY" wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=300s

# 5. Link Secondary Cluster to Argo CD
log_info "Checking if secondary cluster ($SECONDARY_NAME) is linked..."
SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null | grep -v 'in-cluster' || true)

if [ -z "$SECRET_NAME" ]; then
    log_info "Linking secondary cluster ($CTX_SECONDARY) to Argo CD..."
    kubectl config set-context "$CTX_PRIMARY" --namespace=argocd >/dev/null
    kubectl config use-context "$CTX_PRIMARY" >/dev/null

    if argocd cluster add "$CTX_SECONDARY" --yes --core --name cluster-b; then
        log_success "Secondary cluster successfully registered with Argo CD!"
    else
        log_error "Failed to link secondary cluster."
        log_warn "Note: Because secondary cluster endpoint is private (172.16.0.x), ensure this script is run inside the VPC network (or via Bastion/IAP tunnel)."
        exit 1
    fi

    SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null | grep -v 'in-cluster' || true)
else
    log_info "Cluster secret ($SECRET_NAME) already exists. Skipping registration."
fi

if [ -z "$SECRET_NAME" ]; then
    log_error "Cluster secret verification failed after registration."
    exit 1
fi

log_success "Argo CD setup successfully completed!"
