#!/bin/bash
# apply-labels.sh - Applies labels to existing resources without GitOps
# WARNING: This is for emergency use only. Prefer updating manifests in Git.
# Usage: ./apply-labels.sh <namespace> <environment> <owner> <cost-center>

set -euo pipefail

NAMESPACE="${1:-default}"
ENVIRONMENT="${2:-production}"
OWNER="${3:-platform-team}"
COST_CENTER="${4:-eng-platform}"

echo "============================================"
echo "Applying Labels to Existing Resources"
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo "Owner: $OWNER"
echo "Cost Center: $COST_CENTER"
echo "============================================"
echo ""

read -p "This will modify existing resources. Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Function to label resources
label_resources() {
    local kind=$1
    local additional_labels=$2
    
    echo "Labeling $kind in namespace $NAMESPACE..."
    
    kubectl label "$kind" -n "$NAMESPACE" --all \
        app.kubernetes.io/part-of=craftique-ecommerce \
        craftique.io/owner="$OWNER" \
        craftique.io/environment="$ENVIRONMENT" \
        craftique.io/cost-center="$COST_CENTER" \
        $additional_labels \
        --overwrite || true
    
    echo "  ✓ $kind labeled"
}

# Label Deployments
label_resources "deployments" "craftique.io/monitoring=enabled"

# Label StatefulSets  
label_resources "statefulsets" "craftique.io/backup-policy=daily craftique.io/monitoring=enabled"

# Label Services
label_resources "services" ""

# Label ConfigMaps
label_resources "configmaps" ""

# Label PVCs
label_resources "pvc" "craftique.io/backup-policy=daily"

echo ""
echo "============================================"
echo "Labels applied successfully!"
echo ""
echo "IMPORTANT: Update your GitOps manifests to match:"
echo "  craftique-gitops-manifests/apps/"
echo "  craftique-gitops-manifests/infrastructure/"
echo ""
echo "Otherwise, ArgoCD will revert these changes on next sync."
echo "============================================"
