#!/bin/bash

# Auto-resolve the terraform directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../tf"

echo "Changing to Terraform directory: $TF_DIR"
cd "$TF_DIR" || { echo "Failed to cd to $TF_DIR"; exit 1; }

MY_IP=$(curl -s ifconfig.me)/32
echo "Current Workstation IP: $MY_IP"

# Fetch exact values directly from Terraform
PROJECT=$(terraform output -raw project_id)
PRIMARY_NAME=$(terraform output -raw primary_cluster_name)
PRIMARY_LOC=$(terraform output -raw primary_location)
SECONDARY_NAME=$(terraform output -raw secondary_cluster_name)
SECONDARY_LOC=$(terraform output -raw secondary_location)
NAT_PRIMARY_IP=$(terraform output -raw nat_primary_ip 2>/dev/null || echo "35.237.128.165")/32

update_cluster() {
  local CLUSTER_NAME=$1
  local LOCATION=$2

  echo "Fetching current authorized networks for $CLUSTER_NAME..."

  local EXISTING=$(gcloud container clusters describe $CLUSTER_NAME \
    --location $LOCATION \
    --project $PROJECT \
    --format="value[delimiter=','](masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock)")

  # Ensure Workstation IP, Argo CD NAT IP, and Primary Subnet are ALL included
  local REQUIRED_IPS=("$MY_IP" "$NAT_PRIMARY_IP" "10.10.0.0/20")
  
  local NEW_LIST="$EXISTING"
  for IP in "${REQUIRED_IPS[@]}"; do
    if [[ -z "$NEW_LIST" ]]; then
      NEW_LIST="$IP"
    elif [[ "$NEW_LIST" != *"$IP"* ]]; then
      NEW_LIST="$NEW_LIST,$IP"
    fi
  done

  if [[ "$NEW_LIST" == "$EXISTING" ]]; then
    echo " -> All required IPs (Workstation $MY_IP, Argo CD NAT $NAT_PRIMARY_IP) already authorized on $CLUSTER_NAME. Skipping."
    return
  fi

  echo " -> Updating $CLUSTER_NAME with authorized list: $NEW_LIST"
  gcloud container clusters update $CLUSTER_NAME \
    --location $LOCATION \
    --project $PROJECT \
    --enable-master-authorized-networks \
    --master-authorized-networks="$NEW_LIST"
}

update_cluster "$PRIMARY_NAME" "$PRIMARY_LOC"
update_cluster "$SECONDARY_NAME" "$SECONDARY_LOC"

echo "Done"

