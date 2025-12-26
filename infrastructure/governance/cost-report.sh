#!/bin/bash
# cost-report.sh - Generates cost allocation reports based on labels
# Usage: ./cost-report.sh [output-format]
# Formats: text (default), csv, json

set -euo pipefail

OUTPUT_FORMAT="${1:-text}"

# Colors for text output
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "============================================"
echo "Craftique Cost Allocation Report"
echo "Generated: $(date)"
echo "Cluster: $(kubectl config current-context)"
echo "============================================"
echo ""

# Function to count resources by label
count_by_label() {
    local label_key=$1
    local label_value=$2
    
    local deployments=$(kubectl get deployments -A -l "${label_key}=${label_value}" --no-headers 2>/dev/null | wc -l)
    local statefulsets=$(kubectl get statefulsets -A -l "${label_key}=${label_value}" --no-headers 2>/dev/null | wc -l)
    local services=$(kubectl get services -A -l "${label_key}=${label_value}" --no-headers 2>/dev/null | wc -l)
    local pvcs=$(kubectl get pvc -A -l "${label_key}=${label_value}" --no-headers 2>/dev/null | wc -l)
    local pods=$(kubectl get pods -A -l "${label_key}=${label_value}" --no-headers 2>/dev/null | wc -l)
    
    echo "$deployments,$statefulsets,$services,$pvcs,$pods"
}

# Function to print section header
print_section() {
    local title=$1
    echo -e "\n${BOLD}${CYAN}=== $title ===${NC}"
}

# Function to print row in text format
print_row_text() {
    local label=$1
    local counts=$2
    
    IFS=',' read -r deployments statefulsets services pvcs pods <<< "$counts"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "$label" "$deployments" "$statefulsets" "$services" "$pvcs" "$pods"
}

if [ "$OUTPUT_FORMAT" == "text" ]; then
    # Cost by Environment
    print_section "Resources by Environment"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "Environment" "Deployments" "StatefulSets" "Services" "PVCs" "Pods"
    echo "------------------------------------------------------------------------------------"
    
    for env in production staging development; do
        counts=$(count_by_label "craftique.io/environment" "$env")
        print_row_text "$env" "$counts"
    done
    
    # Cost by Cost Center
    print_section "Resources by Cost Center"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "Cost Center" "Deployments" "StatefulSets" "Services" "PVCs" "Pods"
    echo "------------------------------------------------------------------------------------"
    
    for cc in eng-platform eng-backend eng-frontend product-alpha shared-services; do
        counts=$(count_by_label "craftique.io/cost-center" "$cc")
        if [ "$(echo "$counts" | cut -d',' -f1)" != "0" ] || [ "$(echo "$counts" | cut -d',' -f5)" != "0" ]; then
            print_row_text "$cc" "$counts"
        fi
    done
    
    # Cost by Owner
    print_section "Resources by Owner"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "Owner" "Deployments" "StatefulSets" "Services" "PVCs" "Pods"
    echo "------------------------------------------------------------------------------------"
    
    for owner in platform-team backend-team frontend-team devops-team; do
        counts=$(count_by_label "craftique.io/owner" "$owner")
        if [ "$(echo "$counts" | cut -d',' -f1)" != "0" ] || [ "$(echo "$counts" | cut -d',' -f5)" != "0" ]; then
            print_row_text "$owner" "$counts"
        fi
    done
    
    # Public-Facing Resources
    print_section "Public-Facing Resources (Security Focus)"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "Component" "Deployments" "StatefulSets" "Services" "PVCs" "Pods"
    echo "------------------------------------------------------------------------------------"
    
    counts=$(count_by_label "craftique.io/public-facing" "true")
    print_row_text "Public-Facing" "$counts"
    
    # Backup Policy
    print_section "Resources by Backup Policy"
    printf "%-20s | %-12s | %-12s | %-10s | %-8s | %-6s\n" \
        "Backup Policy" "Deployments" "StatefulSets" "Services" "PVCs" "Pods"
    echo "------------------------------------------------------------------------------------"
    
    for policy in daily weekly never; do
        counts=$(count_by_label "craftique.io/backup-policy" "$policy")
        if [ "$(echo "$counts" | cut -d',' -f1)" != "0" ] || [ "$(echo "$counts" | cut -d',' -f5)" != "0" ]; then
            print_row_text "$policy" "$counts"
        fi
    done
    
    echo ""
    echo "============================================"
    echo "Resource Summary:"
    echo "  Total Deployments:   $(kubectl get deployments -A --no-headers | wc -l)"
    echo "  Total StatefulSets:  $(kubectl get statefulsets -A --no-headers | wc -l)"
    echo "  Total Services:      $(kubectl get services -A --no-headers | wc -l)"
    echo "  Total PVCs:          $(kubectl get pvc -A --no-headers | wc -l)"
    echo "  Total Pods:          $(kubectl get pods -A --no-headers | wc -l)"
    echo "============================================"
    
elif [ "$OUTPUT_FORMAT" == "csv" ]; then
    echo "Category,Label,Deployments,StatefulSets,Services,PVCs,Pods"
    
    for env in production staging development; do
        counts=$(count_by_label "craftique.io/environment" "$env")
        echo "Environment,$env,$counts"
    done
    
    for cc in eng-platform eng-backend eng-frontend product-alpha shared-services; do
        counts=$(count_by_label "craftique.io/cost-center" "$cc")
        echo "CostCenter,$cc,$counts"
    done
    
    for owner in platform-team backend-team frontend-team devops-team; do
        counts=$(count_by_label "craftique.io/owner" "$owner")
        echo "Owner,$owner,$counts"
    done
    
elif [ "$OUTPUT_FORMAT" == "json" ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"cluster\": \"$(kubectl config current-context)\","
    echo "  \"environment\": {"
    for env in production staging development; do
        counts=$(count_by_label "craftique.io/environment" "$env")
        IFS=',' read -r deployments statefulsets services pvcs pods <<< "$counts"
        echo "    \"$env\": {\"deployments\": $deployments, \"statefulsets\": $statefulsets, \"services\": $services, \"pvcs\": $pvcs, \"pods\": $pods},"
    done | sed '$ s/,$//'
    echo "  },"
    echo "  \"cost_center\": {"
    for cc in eng-platform eng-backend eng-frontend product-alpha shared-services; do
        counts=$(count_by_label "craftique.io/cost-center" "$cc")
        IFS=',' read -r deployments statefulsets services pvcs pods <<< "$counts"
        echo "    \"$cc\": {\"deployments\": $deployments, \"statefulsets\": $statefulsets, \"services\": $services, \"pvcs\": $pvcs, \"pods\": $pods},"
    done | sed '$ s/,$//'
    echo "  }"
    echo "}"
fi
