#!/bin/bash

# Auto-resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../tf"
REPO_ROOT="$SCRIPT_DIR/../.."

echo "Reading Terraform outputs from $TF_DIR..."
cd "$TF_DIR" || { echo "Failed to cd to $TF_DIR"; exit 1; }
# grab all the terraform outputs. assuming you already applied your tf.
echo "Reading Terraform outputs..."
PROJECT=$(cd "$TF_DIR" && terraform output -raw project_id)
PRIMARY_NAME=$(cd "$TF_DIR" && terraform output -raw primary_cluster_name)
PRIMARY_LOC=$(cd "$TF_DIR" && terraform output -raw primary_location)
SECONDARY_NAME=$(cd "$TF_DIR" && terraform output -raw secondary_cluster_name)
SECONDARY_LOC=$(cd "$TF_DIR" && terraform output -raw secondary_location)
SECONDARY_PRIVATE_IP=$(cd "$TF_DIR" && terraform output -raw secondary_private_endpoint)

# gke context names are super predictable, just gluing them together
CTX_PRIMARY="gke_${PROJECT}_${PRIMARY_LOC}_${PRIMARY_NAME}"
CTX_SECONDARY="gke_${PROJECT}_${SECONDARY_LOC}_${SECONDARY_NAME}"

echo "grabbing creds for the primary cluster..."
gcloud container clusters get-credentials "$PRIMARY_NAME" --location "$PRIMARY_LOC" --project "$PROJECT"

echo "grabbing creds for the secondary cluster..."
gcloud container clusters get-credentials "$SECONDARY_NAME" --location "$SECONDARY_LOC" --project "$PROJECT"

echo "tossing argocd onto the primary cluster..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --kube-context "$CTX_PRIMARY" \
    -f "$REPO_ROOT/kubernetes/platform/argocd/values.yaml"

echo "checking if the secondary cluster is already linked..."
# check if we already have a cluster secret (ignoring the default in-cluster one)
SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name | grep -v 'in-cluster' || true)

if [ -z "$SECRET_NAME" ]; then
    echo "linking the secondary cluster to argo..."
    # forcing the local context over just to be safe
    kubectl config set-context "$CTX_PRIMARY" --namespace=argocd >/dev/null
    kubectl config use-context "$CTX_PRIMARY" >/dev/null
    argocd cluster add "$CTX_SECONDARY" --core --yes

    # fetch the secret name now that we've created it
    SECRET_NAME=$(kubectl --context "$CTX_PRIMARY" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name | grep -v 'in-cluster' || true)
else
    echo "cluster secret ($SECRET_NAME) already exists. skipping add so we don't break the IP patch."
fi

if [ -z "$SECRET_NAME" ]; then
    echo "couldn't find the argo cluster secret even after adding. guess we're done here."
    exit 1
fi

echo "swapping to private ip ($SECONDARY_PRIVATE_IP) so it actually routes internally..."
kubectl --context "$CTX_PRIMARY" -n argocd patch "$SECRET_NAME" \
    --type='merge' \
    -p="{\"stringData\": {\"server\": \"https://$SECONDARY_PRIVATE_IP\"}}"

echo "noicee, deployment and routing are set up."
