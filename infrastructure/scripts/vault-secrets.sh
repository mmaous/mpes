#!/bin/bash
# Push Istio certs and cluster secrets to GCP Secret Manager
set -e

# Setup paths and binary locations
ISTIOCTL_BIN="${1:-istioctl}"
US_CERTS_DIR="${2:-certs/cluster-a}"
EU_CERTS_DIR="${3:-certs/cluster-b}"

# Verify dependencies exist before starting
if ! command -v "$ISTIOCTL_BIN" &> /dev/null; then
  echo "Error: couldn't find istioctl at '$ISTIOCTL_BIN'."
  echo "Usage: ./vault-secrets.sh [istioctl-path] [us-certs-path] [eu-certs-path]"
  exit 1
fi

if [ ! -d "$US_CERTS_DIR" ] || [ ! -d "$EU_CERTS_DIR" ]; then
  echo "Error: missing certificate directories. Check your paths."
  exit 1
fi

echo "Fetching cluster contexts from terraform..."
pushd infrastructure/tf > /dev/null
PRIMARY_CTX=$(terraform output -raw primary_cluster_name)
SECONDARY_CTX=$(terraform output -raw secondary_cluster_name)
PRIMARY_ZONE=$(terraform output -raw primary_location)
SECONDARY_ZONE=$(terraform output -raw secondary_location)
PROJECT_ID=$(terraform output -raw project_id)
popd > /dev/null

CTX_US="gke_${PROJECT_ID}_${PRIMARY_ZONE}_${PRIMARY_CTX}"
CTX_EU="gke_${PROJECT_ID}_${SECONDARY_ZONE}_${SECONDARY_CTX}"

# Helper to handle secret creation and versioning
vault_secret() {
  local secret_name=$1
  local file_path=$2

  echo "Uploading $secret_name..."
  # Create the secret if it doesn't exist, ignore the error if it does
  gcloud secrets create "$secret_name" --replication-policy="automatic" --project="$PROJECT_ID" 2>/dev/null || true
  # Add the new version
  gcloud secrets versions add "$secret_name" --data-file="$file_path" --project="$PROJECT_ID" >/dev/null
}

echo "Pushing certificates to Secret Manager..."

# US certs
vault_secret "istio-us-ca-cert" "$US_CERTS_DIR/ca-cert.pem"
vault_secret "istio-us-ca-key" "$US_CERTS_DIR/ca-key.pem"
vault_secret "istio-us-root-cert" "$US_CERTS_DIR/root-cert.pem"
vault_secret "istio-us-cert-chain" "$US_CERTS_DIR/cert-chain.pem"

# EU certs
vault_secret "istio-eu-ca-cert" "$EU_CERTS_DIR/ca-cert.pem"
vault_secret "istio-eu-ca-key" "$EU_CERTS_DIR/ca-key.pem"
vault_secret "istio-eu-root-cert" "$EU_CERTS_DIR/root-cert.pem"
vault_secret "istio-eu-cert-chain" "$EU_CERTS_DIR/cert-chain.pem"

echo "Generating cross-cluster remote secrets..."

# We need yq to extract the kubeconfig block cleanly
if ! command -v yq &> /dev/null; then
  echo "Error: yq is required for yaml parsing. Please install it."
  exit 1
fi

# Extract and upload US remote secret
"$ISTIOCTL_BIN" create-remote-secret --context="$CTX_US" --name=cluster-a > us-secret.yaml
yq '.stringData."cluster-a"' us-secret.yaml > us-kubeconfig.yaml
vault_secret "istio-remote-secret-us" "us-kubeconfig.yaml"

# Extract and upload EU remote secret
"$ISTIOCTL_BIN" create-remote-secret --context="$CTX_EU" --name=cluster-b > eu-secret.yaml
yq '.stringData."cluster-b"' eu-secret.yaml > eu-kubeconfig.yaml
vault_secret "istio-remote-secret-eu" "eu-kubeconfig.yaml"

# Cleanup temp files
rm us-secret.yaml us-kubeconfig.yaml eu-secret.yaml eu-kubeconfig.yaml

echo "Done. All secrets synced to GCP"
