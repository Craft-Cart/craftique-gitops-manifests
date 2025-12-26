#!/bin/bash
# validate-labels.sh - Validates that all resources have required labels
# Usage: ./validate-labels.sh [namespace]

set -euo pipefail

NAMESPACE="${1:-default}"
FAILED=0
PASSED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "Asset Tagging Validation Report"
echo "Namespace: $NAMESPACE"
echo "Date: $(date)"
echo "============================================"
echo ""

# Required labels for all resources
REQUIRED_LABELS=(
    "app.kubernetes.io/name"
    "app.kubernetes.io/component"
    "app.kubernetes.io/part-of"
    "craftique.io/owner"
    "craftique.io/environment"
    "craftique.io/cost-center"
)

# Function to check labels on a resource
check_labels() {
    local kind=$1
    local name=$2
    local namespace=$3
    
    echo -n "Checking $kind/$name..."
    
    local missing_labels=()
    for label in "${REQUIRED_LABELS[@]}"; do
        if ! kubectl get "$kind" "$name" -n "$namespace" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null | grep -q .; then
            missing_labels+=("$label")
        fi
    done
    
    if [ ${#missing_labels[@]} -eq 0 ]; then
        echo -e " ${GREEN}✓ PASS${NC}"
        ((PASSED++))
    else
        echo -e " ${RED}✗ FAIL${NC}"
        echo -e "  ${YELLOW}Missing labels: ${missing_labels[*]}${NC}"
        ((FAILED++))
    fi
}

echo "=== Checking Deployments ==="
for deployment in $(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    check_labels "deployment" "$deployment" "$NAMESPACE"
done
echo ""

echo "=== Checking StatefulSets ==="
for statefulset in $(kubectl get statefulsets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    check_labels "statefulset" "$statefulset" "$NAMESPACE"
done
echo ""

echo "=== Checking Services ==="
for service in $(kubectl get services -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    # Skip default Kubernetes service
    if [ "$service" != "kubernetes" ]; then
        check_labels "service" "$service" "$NAMESPACE"
    fi
done
echo ""

echo "=== Checking ConfigMaps ==="
for configmap in $(kubectl get configmaps -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    # Skip kube-root-ca.crt (system ConfigMap)
    if [ "$configmap" != "kube-root-ca.crt" ]; then
        check_labels "configmap" "$configmap" "$NAMESPACE"
    fi
done
echo ""

echo "============================================"
echo "Summary:"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo "============================================"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Fix missing labels by updating manifests in:"
    echo "  craftique-gitops-manifests/apps/"
    echo "  craftique-gitops-manifests/infrastructure/"
    echo ""
    exit 1
else
    echo -e "\n${GREEN}All resources have required labels!${NC}"
    exit 0
fi
