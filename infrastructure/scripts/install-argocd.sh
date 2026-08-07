#!/bin/bash
set -e

# Auto-resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../tf"
REPO_ROOT="$SCRIPT_DIR/../."

echo "Reading Terraform outputs from $TF_DIR.."
cd "$TF_DIR" || { echo "Failed to cd to $TF_DIR"; exit 1; }

PROJECT=$(terraform output -raw project_id)
PRIMARY_NAME=$(terraform output -raw primary_cluster_name)
PRIMARY_LOC=$(terraform output -raw primary_location)
SECONDARY_NAME=$(terraform output -raw secondary_cluster_name)
SECONDARY_LOC=$(terraform output -raw secondary_location)

# gke context names
CTX_PRIMARY="gke_${PROJECT}_${PRIMARY_LOC}_${PRIMARY_NAME}"
CTX_SECONDARY="gke_${PROJECT}_${SECONDARY_LOC}_${SECONDARY_NAME}"

echo "Grabbing creds for the primary cluster.."
gcloud container clusters get-credentials "$PRIMARY_NAME" --location "$PRIMARY_LOC" --project "$PROJECT"

echo "Grabbing creds for the secondary cluster.."
gcloud container clusters get-credentials "$SECONDARY_NAME" --location "$SECONDARY_LOC" --project "$PROJECT"

echo "Tossing ArgoCD onto the primary cluster.."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --kube-context "$CTX_PRIMARY" \
    -f "$REPO_ROOT/kubernetes/platform/argocd/values.yaml"

echo "Checking if the secondary cluster is already linked.."
SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name | grep -v 'in-cluster' || true)

if [ -z "$SECRET_NAME" ]; then
    echo "Linking the secondary cluster to Argo CD.."
    kubectl config set-context "$CTX_PRIMARY" --namespace=argocd >/dev/null
    kubectl config use-context "$CTX_PRIMARY" >/dev/null

    # Use context pointing to the secondary cluster, allowing insecure skip for the IP/cert mismatch
    argocd --insecure cluster add "$CTX_SECONDARY" --yes

    SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name | grep -v 'in-cluster' || true)
else
    echo "Cluster secret ($SECRET_NAME) already exists. Skipping add"
fi

if [ -z "$SECRET_NAME" ]; then
    echo "Couldn't find the Argo cluster secret even after adding"
    exit 1
fi

echo "nnoicee, deployment and secure routing are set up!"
