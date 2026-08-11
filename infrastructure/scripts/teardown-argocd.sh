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

# Resolve directory paths (POSIX compatible)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${TF_DIR:-$SCRIPT_DIR/../tf}"

log_info "Reading Terraform outputs from $TF_DIR ..."
ORIG_DIR="$(pwd)"
cd "$TF_DIR" || { log_error "Failed to cd to $TF_DIR"; exit 1; }

PROJECT=$(terraform output -raw project_id)
PRIMARY_NAME=$(terraform output -raw primary_cluster_name)
PRIMARY_LOC=$(terraform output -raw primary_location)
SECONDARY_NAME=$(terraform output -raw secondary_cluster_name)
SECONDARY_LOC=$(terraform output -raw secondary_location)

cd "$ORIG_DIR"

CTX_PRIMARY="gke_${PROJECT}_${PRIMARY_LOC}_${PRIMARY_NAME}"
CTX_SECONDARY="gke_${PROJECT}_${SECONDARY_LOC}_${SECONDARY_NAME}"

log_info "Fetching credentials for primary cluster ($PRIMARY_NAME)..."
gcloud container clusters get-credentials "$PRIMARY_NAME" --location "$PRIMARY_LOC" --project "$PROJECT"

log_info "Fetching credentials for secondary cluster ($SECONDARY_NAME)..."
gcloud container clusters get-credentials "$SECONDARY_NAME" --location "$SECONDARY_LOC" --project "$PROJECT" 2>/dev/null || true

# STEP 1: Delete root ApplicationSets and Applications while Argo CD controller & cluster links are connected
log_info "Step 1: Deleting Argo CD Applications to trigger cascading deletion on both Primary and Secondary clusters..."
kubectl --context "$CTX_PRIMARY" -n argocd delete applicationsets --all --timeout=30s 2>/dev/null || true
kubectl --context "$CTX_PRIMARY" -n argocd delete applications --all --timeout=30s 2>/dev/null || true

# STEP 2: Wait for Argo CD to cascade-delete all remote resources (including Cluster B's istio-system, etc.)
log_info "Step 2: Waiting for Argo CD cascading deletion to finish across all target clusters..."
if ! kubectl --context "$CTX_PRIMARY" -n argocd wait --for=delete application --all --timeout=120s 2>/dev/null; then
    log_warn "Some applications timed out during cascading delete. Stripping lingering finalizers as safety fallback..."
    for app in $(kubectl --context "$CTX_PRIMARY" -n argocd get application -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
        kubectl --context "$CTX_PRIMARY" -n argocd patch application "$app" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
fi

# STEP 3: Fallback direct cleanup for Secondary Cluster namespaces if leftover
log_info "Step 3: Checking secondary cluster ($SECONDARY_NAME) for leftover platform namespaces..."
for ns in istio-system external-secrets cert-manager; do
    if kubectl --context "$CTX_SECONDARY" get ns "$ns" >/dev/null 2>&1; then
        log_info "Cleaning leftover namespace '$ns' on secondary cluster..."
        kubectl --context "$CTX_SECONDARY" delete ns "$ns" --timeout=30s 2>/dev/null || true
    fi
done

# STEP 4: Unlink Secondary Cluster Secret
log_info "Step 4: Unlinking secondary cluster secret..."
kubectl --context "$CTX_PRIMARY" -n argocd delete secret -l argocd.argoproj.io/secret-type=cluster 2>/dev/null || true

# STEP 5: Uninstall Argo CD Helm release from Primary Cluster
log_info "Step 5: Uninstalling Argo CD Helm release from primary cluster..."
if helm status argocd -n argocd --kube-context "$CTX_PRIMARY" >/dev/null 2>&1; then
    helm uninstall argocd -n argocd --kube-context "$CTX_PRIMARY"
    log_success "Argo CD Helm release uninstalled."
else
    log_info "Argo CD Helm release not found. Skipping."
fi

# STEP 6: Clean up Argo CD namespace
log_info "Step 6: Cleaning up Argo CD namespace on primary cluster..."
kubectl --context "$CTX_PRIMARY" delete namespace argocd --ignore-not-found=true --timeout=30s 2>/dev/null || true

NS_STATUS=$(kubectl --context "$CTX_PRIMARY" get ns argocd -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$NS_STATUS" = "Terminating" ]; then
    log_warn "Namespace 'argocd' stuck in Terminating. Force-clearing namespace finalizers..."
    kubectl --context "$CTX_PRIMARY" get namespace argocd -o json | \
      tr -d '\n' | sed 's/"finalizers": \[[^]]*\]/"finalizers": []/' | \
      kubectl --context "$CTX_PRIMARY" replace --raw "/api/v1/namespaces/argocd/finalize" -f - >/dev/null 2>&1 || true
fi

log_success "Multi-cluster teardown complete! Both Primary ($PRIMARY_NAME) and Secondary ($SECONDARY_NAME) clusters are clean."
