#!/bin/bash

# Auto-resolve the terraform directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../tf"

echo "Changing to Terraform directory: $TF_DIR"
cd "$TF_DIR" || { echo "Failed to cd to $TF_DIR"; exit 1; }

MY_IP=$(curl -s ifconfig.me)/32
echo "Current IP: $MY_IP"

# Fetch exact values directly from Terraform
PROJECT=$(terraform output -raw project_id)
PRIMARY_NAME=$(terraform output -raw primary_cluster_name)
PRIMARY_LOC=$(terraform output -raw primary_location)
SECONDARY_NAME=$(terraform output -raw secondary_cluster_name)
SECONDARY_LOC=$(terraform output -raw secondary_location)

update_cluster() {
  local CLUSTER_NAME=$1
  local LOCATION=$2

  echo "Fetching current authorized networks for $CLUSTER_NAME..."

  # Fetch existing IPs
  local EXISTING=$(gcloud container clusters describe $CLUSTER_NAME \
    --location $LOCATION \
    --project $PROJECT \
    --format="join(',', masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock)")

  if [[ -z "$EXISTING" ]]; then
    local NEW_LIST="$MY_IP"
  elif [[ "$EXISTING" == *"$MY_IP"* ]]; then
    echo " -> $MY_IP is already authorized on $CLUSTER_NAME. Skipping."
    return
  else
    local NEW_LIST="$EXISTING,$MY_IP"
  fi

  echo " -> Updating $CLUSTER_NAME with new list: $NEW_LIST"
  gcloud container clusters update $CLUSTER_NAME \
    --location $LOCATION \
    --project $PROJECT \
    --enable-master-authorized-networks \
    --master-authorized-networks="$NEW_LIST"
}

update_cluster "$PRIMARY_NAME" "$PRIMARY_LOC"
update_cluster "$SECONDARY_NAME" "$SECONDARY_LOC"

echo "Done"
